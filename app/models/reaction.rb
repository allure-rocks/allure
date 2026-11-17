# frozen_string_literal: true

require "uri"

# One durable appreciation gesture, on a local workout or a received remote
# note (docs/dev/REACTIONS.md). A reaction is the local counterpart of the
# ActivityPub Like state: `undone_at` keeps the withdrawal history and the
# partial unique indexes allow one active reaction per actor and target.
# Changing the kind withdraws the current Like and creates a new row, so every
# federated activity keeps its own identity.
class Reaction < ApplicationRecord
  KINDS = %w[beer energy coffee like].freeze
  DEFAULT_KIND = "like"
  # The audience the reaction was given through (docs/dev/REACTIONS.md): a
  # reader is named only the reactors whose audience they may read.
  AUDIENCES = %w[public followers].freeze

  belongs_to :actor, inverse_of: :reactions
  belongs_to :workout, optional: true, inverse_of: :reactions
  belongs_to :remote_note, optional: true, inverse_of: :reactions

  validates :uri, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :audience, inclusion: { in: AUDIENCES }
  validate :uri_is_absolute
  validate :single_target

  scope :active, -> { where(undone_at: nil) }

  def active? = undone_at.nil?

  def target = workout || remote_note

  def remote_target? = remote_note_id.present?

  def undo!(at: Time.current)
    update!(undone_at: at) unless undone_at.present?
    self
  end

  private

  def single_target
    errors.add(:base, :invalid) unless [ workout, remote_note ].compact.one?
  end

  def uri_is_absolute
    parsed = URI.parse(uri.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank?
    errors.add(:uri, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:uri, :invalid)
  end
end
