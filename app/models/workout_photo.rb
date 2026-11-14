# frozen_string_literal: true

class WorkoutPhoto < ApplicationRecord
  include HasShortId

  STATUSES = %w[processing ready failed].freeze
  FAILURE_REASONS = %w[unreadable too_large_dimensions processing_error quota_exceeded].freeze
  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic].freeze
  LOCATION_SOURCES = %w[exif time manual none cleared].freeze

  belongs_to :workout, inverse_of: :photos
  belongs_to :user
  has_one_attached :original, dependent: :purge_later
  has_one_attached :display, dependent: :purge_later
  has_one_attached :thumbnail, dependent: :purge_later

  enum :status, STATUSES.index_with(&:itself)
  validates :status, inclusion: { in: STATUSES }
  validates :failure_reason, inclusion: { in: FAILURE_REASONS }, allow_nil: true
  validates :original_content_type, inclusion: { in: CONTENT_TYPES }
  validates :caption, length: { maximum: Allure::Photos::Config::MAX_CAPTION }
  validates :position, :bytes_total, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :location_source, inclusion: { in: LOCATION_SOURCES }
  validate :owner_matches_workout

  def placed? = !location.nil?

  private

  def owner_matches_workout
    errors.add(:user, :invalid) unless workout&.user_id == user_id && !workout.credit?
  end
end
