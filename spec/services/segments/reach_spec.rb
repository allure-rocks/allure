# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Reach do
  let(:athlete) { create(:user) }
  let(:sport) { create(:sport) }
  let(:segment) { create(:segment, sport:).tap { it.update_column(:visibility, "public") }.reload }

  around do |example|
    original = ENV["FEDERATION_RESTRICTED_ENABLED"]
    ENV["FEDERATION_RESTRICTED_ENABLED"] = "true"
    example.run
  ensure
    ENV["FEDERATION_RESTRICTED_ENABLED"] = original
  end

  def run!(followers: false, route: true, published: true)
    workout = create(:workout, user: athlete, sport:)
    if published
      profile = followers ? build(:publishing_profile, :followers, user: athlete) : build(:publishing_profile, user: athlete)
      profile.settings = profile.settings.merge("route" => route)
      create(:workout_publication, workout:, publishing_profile: profile, status: "active")
    end
    create(:segment_effort, segment:, workout:, user: athlete, sport:)
  end

  def reach = described_class.new(segment:, user: athlete).call

  it "is nil without an effort or a board" do
    expect(reach).to be_nil

    run!
    segment.update_column(:visibility, "private")
    expect(described_class.new(segment: segment.reload, user: athlete).call).to be_nil
  end

  it "states the widest audience of a publication sharing the route" do
    run!(followers: true)
    expect(reach).to eq("followers")

    run!
    expect(reach).to eq("public")
  end

  it "names why nobody sees the athlete" do
    run!(published: false)
    expect(reach).to eq("unpublished")

    run!(route: false)
    expect(reach).to eq("route_hidden")

    create(:privacy_zone, user: athlete, latitude: 45.0719, longitude: 6.4083, radius_meters: 1000)
    expect(reach).to eq("zoned")

    create(:segment_opt_out, segment:, user: athlete)
    expect(reach).to eq("opted_out")
  end

  it "reads a followers publication as reaching followers with restricted federation off" do
    run!(followers: true)
    ENV["FEDERATION_RESTRICTED_ENABLED"] = "false"

    expect(reach).to eq("followers")
  end
end
