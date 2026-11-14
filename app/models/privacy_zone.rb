# frozen_string_literal: true

class PrivacyZone < ApplicationRecord
  RADIUS_RANGE = 1..10_000

  belongs_to :user, inverse_of: :privacy_zones

  scope :active, -> { where(active: true) }

  before_validation :assign_center_from_coordinates

  validates :name, length: { maximum: 120 }, allow_nil: true
  validates :latitude, :longitude, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :radius_meters,
            numericality: { only_integer: true, in: RADIUS_RANGE }
  validates :active, inclusion: { in: [ true, false ] }
  validates :center, presence: true
  validate :center_is_wgs84_point

  def latitude = @latitude.nil? ? center&.y : @latitude
  def longitude = @longitude.nil? ? center&.x : @longitude

  def latitude=(value)
    @latitude = value
  end

  def longitude=(value)
    @longitude = value
  end

  def to_value
    Allure::Federation::Privacy::Zone.new(
      center: [ longitude, latitude ],
      radius_meters:
    )
  end

  private

  def assign_center_from_coordinates
    return unless latitude.present? && longitude.present?

    self.center = RGeo::Geographic.spherical_factory(srid: 4326).point(Float(longitude), Float(latitude))
  rescue ArgumentError, TypeError
    self.center = nil
  end

  def center_is_wgs84_point
    return if center.blank?

    valid_point = center.is_a?(RGeo::Feature::Point) && center.srid == 4326 &&
      center.x.between?(-180, 180) && center.y.between?(-90, 90)
    errors.add(:center, :invalid) unless valid_point
  end
end
