# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::DeleteAccount do
  let(:now) { Time.utc(2026, 9, 11, 12) }
  let(:user) { create(:user) }
  let!(:actor) { create(:local_actor, user:) }

  it "withdraws publications, tombstones the actor, and destroys the user" do
    publication = create(:workout_publication, workout: create(:workout, user:))

    described_class.new(user:, now:).call!

    expect(User.exists?(user.id)).to be(false)
    expect(publication.reload).to be_deleted
    expect(publication.workout_id).to be_nil
    expect(actor.reload).to be_tombstoned
    expect(actor.user_id).to be_nil
    expect(
      FederationOutboxEvent.where(activity_type: "Delete", subject_type: "Actor", object_uri: actor.uri)
    ).to exist
  end

  it "destroys a user that never provisioned an actor" do
    plain_user = create(:user)

    described_class.new(user: plain_user, now:).call!

    expect(User.exists?(plain_user.id)).to be(false)
  end

  it "withdraws the account's live participations and their notices" do
    owner = create(:user)
    owner_actor = create(:local_actor, user: owner)
    source = create(:workout, user: owner)
    participation = create(:workout_participation, :pending, workout: source, participant_actor: actor)
    Notifications::Create.new(user:, kind: "participation_requested", actor: owner_actor, subject: participation).call!

    counterpart = create(:user)
    counterpart_actor = create(:local_actor, user: counterpart)
    own_workout = create(:workout, user:)
    own_participation = create(:workout_participation, :pending, workout: own_workout, participant_actor: counterpart_actor)
    Notifications::Create.new(user: counterpart, kind: "participation_requested", actor:, subject: own_participation).call!

    described_class.new(user:, now:).call!

    expect(participation.reload).to be_withdrawn
    # The owner-side row cascades with its workout, whose destroy withdrew its notice.
    expect(WorkoutParticipation.exists?(own_participation.id)).to be(false)
    expect(Notification.where(kind: "participation_requested")).to be_empty
  end

  describe "phases (PLAN_ACCOUNT.md §2.2)" do
    it "cuts the account off before anything else and audits the deletion once" do
      user.sessions.create!(user_agent: "RSpec", ip_address: "192.0.2.1", last_seen_at: now)
      ApiToken.issue!(user:, name: "Spec client", scopes: %w[read])
      create_list(:workout, 3, user:)

      expect(described_class.new(user:, now:).call!(limit: 1)).to be(false)

      expect(user.reload.deletion_started_at).to eq(now)
      expect(user.sessions).to be_empty
      expect(user.api_tokens).to be_empty
      expect(user.workouts.count).to eq(2)
      expect(actor.reload).to be_tombstoned
      expect(AdminEvent.where(action: "account_deleted").sole.metadata)
        .to eq("username" => user.username, "by" => "operator")
    end

    it "resumes where it stopped and finishes with the row" do
      create_list(:workout, 3, user:)
      service = described_class.new(user:, now:)

      expect(service.call!(limit: 2)).to be(false)
      expect(described_class.new(user: user.reload, now:).call!(limit: 2)).to be(true)

      expect(User.exists?(user.id)).to be(false)
      expect(AdminEvent.where(action: "account_deleted").count).to eq(1)
    end

    it "keeps who asked when the deletion was scheduled" do
      user.update!(deletion_requested_at: now, deletion_scheduled_at: now, deletion_requested_by: "self")

      described_class.new(user:, now:).call!

      expect(AdminEvent.where(action: "account_deleted").sole.metadata["by"]).to eq("self")
    end

    it "purges a demanded purge while the schedule stands" do
      user.update!(deletion_requested_at: now, deletion_scheduled_at: now, deletion_requested_by: "self")

      expect(described_class.new(user:, now:, require_scheduled: true).call!).to be(true)

      expect(User.exists?(user.id)).to be(false)
    end

    it "refuses a demanded purge whose deletion was cancelled first" do
      user.update!(deletion_requested_at: now, deletion_scheduled_at: now, deletion_requested_by: "self")
      Users::DeletionSchedule.new(user:).cancel!

      expect { described_class.new(user:, now:, require_scheduled: true).call! }
        .to raise_error(described_class::Cancelled)

      expect(user.reload).to be_persisted
      expect(user.deletion_started_at).to be_nil
      expect(user.deletion_scheduled_at).to be_nil
      expect(actor.reload).not_to be_tombstoned
    end

    it "deletes the account's connected services before any workout" do
      connection = create(:import_connection, :linked, user:)
      create(:workout, user:)

      described_class.new(user:, now:).call!(limit: 0)

      expect(ImportConnection.exists?(connection.id)).to be(false)
      expect(user.workouts.count).to eq(1)
    end

    it "detaches and keeps a participant's credit row" do
      source = create(:workout, user:)
      participant = create(:user)
      credit = create(:workout, :credit, user: participant, credited_from: source, credited_by: actor)

      described_class.new(user:, now:).call!

      expect(credit.reload.credited_from_workout_id).to be_nil
      expect(credit.credit_detached_at).to be_present
    end

    it "stops every live provider renewal before the rows are purged" do
      subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
                            customer_id: "cus_123", tier: "coffee")
      create(:funding_contribution, :subscription, funding_subscription: subscription)
      state = Allure::Funding::SubscriptionState.new(subscription_id: "sub_123", customer_id: "cus_123",
                                                     tier: "coffee", status: "active",
                                                     cancel_at_period_end: true, canceled_at: nil)
      ENV["FUNDING_ENABLED"] = "false"
      allow(Funding::Providers::Stripe).to receive(:cancel).with(subscription:).and_return(state)

      described_class.new(user:, now:).call!

      expect(Funding::Providers::Stripe).to have_received(:cancel).with(subscription:)
      expect(User.exists?(user.id)).to be(false)
    end

    it "cancels a subscription bound by a late verified notification during the deletion window (PAY-101)" do
      # The checkout completed before deletion was scheduled; its initial
      # notifications arrive only after the account is deactivated.
      reference = Funding::Reference.generate(user:, tier: "coffee")
      binding = Allure::Funding::CheckoutBinding.new(subscription_id: "sub_late", customer_id: "cus_late",
                                                     tier: "coffee", reference:, created_at: Time.current)
      Users::DeletionSchedule.new(user:).schedule!(by: "self")
      subscription = Funding::BindSubscription.call(provider: "stripe", binding:)
      expect(subscription.reload.user).to eq(user)

      state = Allure::Funding::SubscriptionState.new(subscription_id: "sub_late", customer_id: "cus_late",
                                                     tier: "coffee", status: "active",
                                                     cancel_at_period_end: true, canceled_at: nil)
      allow(Funding::Providers::Stripe).to receive(:cancel).with(subscription:).and_return(state)

      described_class.new(user:, now:).call!

      expect(Funding::Providers::Stripe).to have_received(:cancel).with(subscription:)
      expect(User.exists?(user.id)).to be(false)
    end

    it "stays blocked when the provider's 404 cannot be explained by the original account (PAY-104)" do
      subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_404",
                                              customer_id: "cus_404", tier: "coffee")
      allow(Funding::Providers::Stripe).to receive(:cancel)
        .and_raise(Allure::Funding::Stripe::Error.new("Stripe API answered HTTP 404", status: 404))

      expect { described_class.new(user:, now:).call! }
        .to raise_error(Allure::Funding::Stripe::Error, /404/)

      # The purge is blocked before any identifier is purged: the account and
      # its billing association remain available for investigation and retry.
      expect(User.exists?(user.id)).to be(true)
      expect(FundingSubscription.exists?(subscription.id)).to be(true)
      expect(user.reload.deletion_started_at).to be_present
    end

    it "keeps a late-bound subscription live when the deletion is cancelled within the window (PAY-101)" do
      reference = Funding::Reference.generate(user:, tier: "coffee")
      binding = Allure::Funding::CheckoutBinding.new(subscription_id: "sub_late", customer_id: "cus_late",
                                                     tier: "coffee", reference:, created_at: Time.current)
      Users::DeletionSchedule.new(user:).schedule!(by: "self")
      subscription = Funding::BindSubscription.call(provider: "stripe", binding:)
      allow(Funding::Providers::Stripe).to receive(:cancel)

      Users::DeletionSchedule.new(user:).cancel!

      expect(user.reload).not_to be_deactivated
      expect(subscription.reload).to have_attributes(user:, status: "incomplete")
      expect(Funding::Providers::Stripe).not_to have_received(:cancel)
    end
  end

  describe "the username afterwards (PLAN_ACCOUNT.md §2.1)" do
    it "is never handed out again" do
      federated = create(:user)
      Federation::ActorProvisioner.new(user: federated).call!
      username = federated.username
      described_class.new(user: federated, now:).call!

      newcomer = build(:user, username:)

      expect(newcomer).not_to be_valid
      expect(newcomer.errors.details[:username]).to include(error: :retired)

      # Sign-up and provider onboarding validate under :self_registration;
      # the creation-time check must not depend on the context.
      expect(newcomer.valid?(:self_registration)).to be(false)
      expect(newcomer.errors.details[:username]).to include(error: :retired)
    end
  end
end
