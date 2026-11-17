# frozen_string_literal: true

# One photo frozen into a publication (docs/dev/PHOTOS.md): its own stripped
# WebP copies, never the owner's files, so editing or deleting the source
# photo leaves the publication as it was published. Immutable once written;
# the publication's cleanup purges it with the rest of its media.
class WorkoutPublicationPhoto < ApplicationRecord
  include HasShortId

  MAX_PER_PUBLICATION = Allure::Photos::Config::MAX_PER_WORKOUT

  belongs_to :workout_publication, inverse_of: :photos
  has_one_attached :display, dependent: :purge_later
  has_one_attached :thumbnail, dependent: :purge_later

  attr_readonly :uuid, :workout_publication_id, :position, :width, :height, :caption, :distance

  validates :position, numericality: { only_integer: true, in: 0...MAX_PER_PUBLICATION }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }
  validates :caption, length: { maximum: Allure::Photos::Config::MAX_CAPTION }
  validates :distance, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(:position) }
end
