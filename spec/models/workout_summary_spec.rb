# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutSummary do
  subject(:summary) { build(:workout_summary) }

  it { is_expected.to belong_to(:workout) }
  it { is_expected.to allow_value(nil).for(:last_error) }
  it { is_expected.not_to allow_value("boom").for(:last_error) }

  it "accepts only the documented statuses" do
    summary.status = "ready"
    expect(summary).to be_ready

    expect { summary.status = "bogus" }.to raise_error(ArgumentError)
  end

  it "starts pending with an empty snapshot" do
    summary = described_class.new(workout: create(:workout), locale: "fr")

    expect(summary.status).to eq("pending")
    expect(summary.pending?).to be(true)
    expect(summary.settled?).to be(false)
    expect(summary.facts).to eq([])
    expect(summary.sentences).to eq([])
  end

  it "holds one row per workout" do
    workout = create(:workout)
    create(:workout_summary, workout:)

    duplicate = build(:workout_summary, workout:)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:workout_id]).to be_present
  end

  it "keeps its snapshot and its sentences as arrays" do
    summary = build(:workout_summary)
    summary.facts = { "id" => "baseline:distance" }
    summary.sentences = "une phrase"

    expect(summary).not_to be_valid
    expect(summary.errors[:facts]).to be_present
    expect(summary.errors[:sentences]).to be_present
  end
end
