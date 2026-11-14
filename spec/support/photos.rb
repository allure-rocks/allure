# frozen_string_literal: true

module PhotoHelpers
  def with_photo_env(values)
    previous = ENV.to_h.slice(*values.keys)
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    values.each_key { |key| ENV[key] = previous[key] }
  end

  DEFAULT_PHOTO_EXIF = {
    "exif-ifd2-DateTimeOriginal" => "2026:05:01 10:20:30",
    "exif-ifd3-GPSLatitudeRef" => "N",
    "exif-ifd3-GPSLatitude" => "45/1 10/1 30/1"
  }.freeze

  # A synthetic JPEG whose EXIF fields libvips writes as given, e.g.
  # `photo_exif(taken_at: "2026:08:23 06:00:30", offset: "+00:00", lon: 6.408, lat: 45.072)`.
  def photo_bytes(width: 64, height: 48, metadata: true, orientation: nil, exif: DEFAULT_PHOTO_EXIF)
    image = (Vips::Image.black(width, height, bands: 3) + 120).copy
    image.set_type(GObject::GINT_TYPE, "orientation", orientation) if orientation
    exif.each { |name, value| image.set_type(GObject::GSTR_TYPE, name, value) } if metadata
    image.jpegsave_buffer
  end

  def photo_exif(taken_at: nil, offset: nil, lon: nil, lat: nil)
    fields = {}
    fields["exif-ifd2-DateTimeOriginal"] = taken_at if taken_at
    fields["exif-ifd2-OffsetTimeOriginal"] = offset if offset
    if lon && lat
      fields["exif-ifd3-GPSLatitudeRef"] = lat.negative? ? "S" : "N"
      fields["exif-ifd3-GPSLatitude"] = "#{(lat.abs * 1_000_000).round}/1000000 0/1 0/1"
      fields["exif-ifd3-GPSLongitudeRef"] = lon.negative? ? "W" : "E"
      fields["exif-ifd3-GPSLongitude"] = "#{(lon.abs * 1_000_000).round}/1000000 0/1 0/1"
    end
    fields
  end

  def photo_upload(body = photo_bytes)
    Rack::Test::UploadedFile.new(StringIO.new(body), "image/jpeg", true, original_filename: "test.jpg")
  end
end

RSpec.configure { |config| config.include PhotoHelpers }
