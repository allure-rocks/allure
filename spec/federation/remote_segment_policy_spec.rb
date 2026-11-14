# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteSegmentPolicy do
  let(:segment) { create(:remote_segment) }
  let(:user) { create(:user) }

  def allowed?(principal:, resource: :segment, segment: self.segment)
    described_class.new(segment:, principal:).allowed?(resource:)
  end

  it "serves a public course to a signed-in account" do
    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(user))).to be(true)
  end

  it "denies anonymous visitors" do
    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(nil))).to be(false)
  end

  it "denies an inactive course and unknown resources" do
    segment.mark_deleted!

    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(user))).to be(false)
    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(user), resource: :unknown)).to be(false)
  end

  it "gates the track and media on the representation" do
    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(user), resource: :media)).to be(true)
    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(user), resource: :track)).to be(false)

    segment.reload
    RemoteSegment.where(id: segment.id).update_all(
      representation: segment.representation.merge(
        "track" => {
          "type" => "FeatureCollection",
          "features" => [
            {
              "type" => "Feature",
              "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
              "properties" => { "segment_index" => 0 }
            }
          ]
        }
      )
    )
    segment.reload

    expect(allowed?(principal: Workouts::PublicationPrincipal.browser(user), resource: :track)).to be(true)
  end

  describe "a followers-only course" do
    let(:segment) { create(:remote_segment, audience: "followers") }
    let(:viewer) { create(:user) }

    it "requires an active entitlement" do
      expect(allowed?(principal: Workouts::PublicationPrincipal.browser(viewer))).to be(false)

      create(
        :remote_segment_recipient,
        remote_segment: segment,
        recipient_actor: Federation::ActorProvisioner.new(user: viewer).call!
      )

      expect(allowed?(principal: Workouts::PublicationPrincipal.browser(viewer))).to be(true)
    end
  end
end
