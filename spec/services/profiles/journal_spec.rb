# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiles::Journal do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:public_profile) { create(:publishing_profile, user: owner) }
  let(:scope) { WorkoutPublication.served_to(viewer).where(workout_id: owner.workouts.select(:id)) }

  def publication(title, sport: catalog_sport("running"), started_at: 1.day.ago, **options)
    workout = create(:workout, user: owner, sport:, started_at:)
    create(:workout_publication, workout:, publishing_profile: public_profile, representation: {
      "title" => title, "sport_slug" => sport.slug, "started_at" => started_at.iso8601, "metrics" => {}
    }, **options)
  end

  def journal(**options)
    described_class.new(scope:, viewer:, **options)
  end

  it "counts only accessible active publications, not private, scheduled or deleted outings" do
    shared = publication("Visible run")
    create(:workout, user: owner, sport: catalog_sport("rowing"))
    publication("Followers ride", sport: catalog_sport("cycling"), publishing_profile: create(:publishing_profile, :followers, user: owner))
    publication("Scheduled hike", sport: catalog_sport("hiking"), status: "scheduled", scheduled_for: 1.day.from_now)
    publication("Deleted trail", sport: catalog_sport("trail"), status: "deleted", deleted_at: Time.current)

    expect(journal.total_count).to eq(1)
    expect(journal.sports.map(&:key)).to eq([ "running" ])
    expect(journal.relation).to eq([ shared ])
  end

  it "orders and filters by frozen dates and sports after the owner edits the source" do
    old = publication("Old run", started_at: 2.years.ago)
    recent = publication("Recent run")
    recent.workout.update!(sport: catalog_sport("cycling"), started_at: 4.years.ago)
    old.workout.update!(started_at: Time.current)

    expect(journal.relation).to eq([ recent, old ])
    expect(journal(sport: "running", period: "days30").relation).to eq([ recent ])
    expect(journal.sports.map(&:key)).to eq([ "running" ])
  end

  it "keeps all history by default and ignores malformed or inaccessible filter choices" do
    old = publication("Old run", started_at: 2.years.ago)

    expect(journal.period).to eq("all")
    expect(journal.relation).to eq([ old ])
    expect(journal(period: "bad", sport: "rowing").selected_sport).to be_nil
    expect(journal(period: [ "year" ], sport: [ "running" ]).relation).to eq([ old ])
  end

  it "uses the viewer's calendar boundaries rather than the server's date" do
    viewer.update!(time_zone: "Pacific/Auckland")
    travel_to(Time.utc(2025, 12, 31, 12)) do
      before = publication("Before local year", started_at: Time.utc(2025, 12, 31, 10, 59))
      after = publication("After local year", started_at: Time.utc(2025, 12, 31, 11))

      expect(journal(period: "year").relation).to eq([ after ])
      expect(journal(period: "year").relation).not_to include(before)
    end
  end

  it "retains the active sport with zero results while counting the other sports in the period" do
    publication("Old run", started_at: 2.years.ago)
    publication("Recent ride", sport: catalog_sport("cycling"))

    filtered = journal(sport: "running", period: "days30")

    expect(filtered.relation).to be_empty
    expect(filtered.selector_sports.map { |entry| [ entry.key, entry.count ] }).to eq([ [ "cycling", 1 ], [ "running", 0 ] ])
    expect(filtered.mix?).to be(false)
    expect(journal.mix?).to be(true)
    expect(journal(period: "days30").mix?).to be(false)
  end

  it "counts a multi-audience workout once, from the narrowest snapshot served to the reader" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    public_copy = publication("Public copy", sport: catalog_sport("cycling"))
    followers_copy = create(:workout_publication, :with_followers, workout: public_copy.workout,
      representation: { "title" => "Followers copy", "sport_slug" => "running", "started_at" => Time.current.iso8601, "metrics" => {} })
    owner_journal = described_class.new(
      scope: WorkoutPublication.served_to(owner).where(workout_id: owner.workouts.select(:id)), viewer: owner
    )

    expect(owner_journal.total_count).to eq(1)
    expect(owner_journal.sports.map(&:key)).to eq([ "running" ])
    expect(owner_journal.relation).to eq([ followers_copy ])
    expect(journal.sports.map(&:key)).to eq([ "cycling" ])
  end

  it "hands the feed card the exact authorized publication, even for the owner" do
    shared = publication("Frozen title")
    shared.workout.update!(title: "Unpublished edit")

    item = journal.items_for(journal.relation.includes(:workout)).sole

    expect(item.kind).to eq("local")
    expect(item.publication).to eq(shared)
    expect(item.record).to eq(shared.workout)
  end

  it "does not invent a missing remote date and keeps the neutral sport fallback" do
    actor = create(:actor)
    dated = create(:remote_note, actor:, sport_label: "Hiking")
    undated = create(:remote_note, actor:, sport_label: nil, started_at: nil,
      representation: { "title" => "Undated", "metrics" => {} })
    remote = described_class.new(scope: RemoteNote.where(actor:), viewer:)

    expect(remote.relation).to eq([ dated, undated ])
    expect(remote.sports.map(&:key)).to include("label:")
    expect(remote.sports.find { |entry| entry.key == "label:" }.sport).to be_a(Federation::RemoteNoteView::SportFallback)
    expect(described_class.new(scope: RemoteNote.where(actor:), viewer:, sport: "label:").relation).to eq([ undated ])
  end

  it "groups remote label variants like the existing sport presentation" do
    actor = create(:actor)
    create(:remote_note, actor:, sport_label: "Hiking")
    create(:remote_note, actor:, sport_label: " hiking ")
    remote = described_class.new(scope: RemoteNote.where(actor:), viewer:, sport: "label:Hiking")

    expect(remote.sports.map(&:key)).to eq([ "label:hiking" ])
    expect(remote.sports.sole.count).to eq(2)
    expect(remote.selected_sport.sport).to eq(catalog_sport("hiking"))
    expect(remote.relation.count).to eq(2)
  end
end
