# frozen_string_literal: true

require "rails_helper"

# PLAN_PHOTOS.md §5: what a publication freezes of the owner's photos.
RSpec.describe "Publishing workout photos" do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let(:factory) { RGeo::Geographic.spherical_factory(srid: 4326) }
  let(:settings) { { "photos" => true, "photo_captions" => true, "photo_positions" => true } }
  let(:profile) do
    create(:publishing_profile, :without_endpoint_masks, user:,
                                                         settings: PublishingProfile::DEFAULT_SETTINGS.merge("mask_start" => false, "mask_finish" => false).merge(settings))
  end

  # About 1.1 km due north, one point every ~111 m.
  before do
    points = (0..10).map do |index|
      { "t" => index * 30, "d" => index * 111.2, "lat" => 45.07 + (index * 0.001), "lon" => 6.4, "ele" => 100.0 }
    end
    create(:track_segment, workout:, points:, duration: 300, moving_time: 300, pause_time: 0, distance: 1112.0)
  end

  def ready_photo(caption: nil, at: nil)
    photo = Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(photo_bytes(width: 2400, height: 1600, exif: photo_exif(lon: 6.4, lat: 45.07))))
    Workouts::PhotoProcessJob.perform_now(photo)
    photo.reload.update!(caption:)
    if at
      Workouts::PhotoPlacement.new(workout:).place(photo, longitude: at[0], latitude: at[1])
    else
      Workouts::PhotoPlacement.new(workout:).clear(photo)
    end
    photo.reload
  end

  def publish!(**options)
    publication = Workouts::Publisher.new(user:, workout:, profile:, **options).call!
    Workouts::ScheduledPublicationActivation.new(publication:, force: true).call!
    publication.reload
  end

  it "freezes stripped copies with their caption and a distance along the published route" do
    photo = ready_photo(caption: "Col", at: [ 6.4, 45.075 ])

    publication = publish!
    entry = publication.representation.fetch("photos").sole
    copy = publication.photos.sole

    expect(entry.keys).to match_array(%w[id width height caption distance])
    expect(entry).to include("id" => copy.to_param, "caption" => "Col", "width" => 1600, "height" => copy.height)
    expect(copy.height).to be_between(1066, 1067)
    expect(entry["distance"]).to be_within(1).of(556)
    image = Vips::Image.new_from_buffer(copy.display.download, "")
    expect(image.get_fields.grep(/exif|xmp|icc/)).to be_empty
    expect(copy.display.blob).not_to eq(photo.display.blob)
    expect(entry.to_json).not_to include("45.07", "6.4", "taken")
  end

  it "leaves the publication as published when the owner later edits or deletes the photo" do
    photo = ready_photo(caption: "Avant")
    publication = publish!

    photo.update!(caption: "Après")
    photo.destroy!

    expect(publication.reload.photos.sole.caption).to eq("Avant")
    expect(publication.photos.sole.display).to be_attached
  end

  context "when the profile shares neither captions nor positions" do
    let(:settings) { { "photos" => true } }

    it "shares the photos alone" do
      ready_photo(caption: "Private words", at: [ 6.4, 45.075 ])

      entry = publish!.representation.fetch("photos").sole

      expect(entry.keys).to match_array(%w[id width height])
    end
  end

  context "when the profile does not share photos" do
    let(:settings) { {} }

    it "freezes none" do
      ready_photo

      publication = publish!

      expect(publication.representation).not_to have_key("photos")
      expect(publication.photos).to be_empty
    end
  end

  context "with a photo taken inside a privacy zone" do
    before { create(:privacy_zone, user:, center: factory.point(6.4, 45.079), radius_meters: 150) }

    it "leaves it out by default" do
      kept = ready_photo(at: [ 6.4, 45.072 ])
      ready_photo(at: [ 6.4, 45.079 ])

      publication = publish!

      expect(publication.photos.count).to eq(1)
      expect(publication.representation["photos"].sole["distance"]).to be_within(1).of(kept.track_distance)
    end

    it "requires the acknowledgement for an explicit choice, then shares it without a position" do
      sensitive = ready_photo(at: [ 6.4, 45.079 ])

      expect { publish!(photo_ids: [ sensitive.to_param ]) }
        .to raise_error(Workouts::Publisher::PublicationError) { expect(it.code).to eq("photos_unacknowledged") }

      entry = publish!(photo_ids: [ sensitive.to_param ], photos_acknowledged: true).representation["photos"].sole
      expect(entry).not_to have_key("distance")
    end

    it "treats an EXIF position inside a zone as sensitive even when the photo is not placed" do
      photo = ready_photo
      photo.update!(exif_location: factory.point(6.4, 45.0791))

      expect(publish!.photos).to be_empty
    end
  end

  it "shares no photo when the owner unticked them all" do
    ready_photo

    expect(publish!(photo_ids: []).photos).to be_empty
  end

  it "purges the copies with the rest of the media once the withdrawal settled" do
    ready_photo
    publication = publish!

    Workouts::PublicationWithdrawal.new(user:, workout:, publication:).call!
    publication.reload
    allow(Workouts::PublicationCleanup).to receive(:eligible?).and_return(true)
    Workouts::PublicationCleanup.new(publication:).call!

    expect(publication.reload.photos).to be_empty
    expect(publication.representation).not_to have_key("photos")
  end
end
