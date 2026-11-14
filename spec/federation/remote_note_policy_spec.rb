# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteNotePolicy do
  let(:note) { create(:remote_note) }
  let(:viewer) { create(:user) }

  def policy(note: self.note, principal:)
    described_class.new(note:, principal:)
  end

  it "allows any signed-in local account to see a public note" do
    expect(policy(principal: Workouts::PublicationPrincipal.browser(viewer)).allowed?).to be(true)
  end

  it "never allows anonymous viewers" do
    expect(policy(principal: Workouts::PublicationPrincipal.anonymous).allowed?).to be(false)
  end

  it "requires an active entitlement for a followers note" do
    note.update_column(:audience, "followers")

    expect(policy(principal: Workouts::PublicationPrincipal.browser(viewer)).allowed?).to be(false)

    actor = Federation::ActorProvisioner.new(user: viewer).call!
    create(:remote_note_recipient, remote_note: note, recipient_actor: actor)

    expect(policy(principal: Workouts::PublicationPrincipal.browser(viewer)).allowed?).to be(true)
  end

  it "ignores a withdrawn entitlement" do
    note.update_column(:audience, "followers")
    actor = Federation::ActorProvisioner.new(user: viewer).call!
    recipient = create(:remote_note_recipient, remote_note: note, recipient_actor: actor)
    recipient.withdraw!(reason: "unfollow")

    expect(policy(principal: Workouts::PublicationPrincipal.browser(viewer)).allowed?).to be(false)
  end

  it "denies deleted notes and unknown resources" do
    note.mark_deleted!

    expect(policy(principal: Workouts::PublicationPrincipal.browser(viewer)).allowed?).to be(false)
    expect(policy(principal: Workouts::PublicationPrincipal.browser(viewer)).allowed?(resource: :bogus)).to be(false)
  end

  it "allows comments unless the origin's profile closed them" do
    principal = Workouts::PublicationPrincipal.browser(viewer)
    closed = create(:remote_note, representation: note.representation.merge("comments_closed" => true))

    expect(policy(principal:).allowed?(resource: :comment)).to be(true)
    expect(policy(note: closed, principal:).allowed?(resource: :comment)).to be(false)
    expect(policy(note: closed, principal:).allowed?(resource: :note)).to be(true)
    expect(policy(principal: Workouts::PublicationPrincipal.anonymous).allowed?(resource: :comment)).to be(false)
  end
end
