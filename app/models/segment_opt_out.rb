# frozen_string_literal: true

# docs/dev/SEGMENTS.md: leaderboard participation is opt-out. A row excludes
# one athlete from one segment's board; every matched athlete is ranked
# otherwise, the owner included. There is no implicit participant and no cached
# listing state: eligibility is derived on read by `Segments::Listing`.
class SegmentOptOut < ApplicationRecord
  belongs_to :segment, inverse_of: :segment_opt_outs
  belongs_to :user, inverse_of: :segment_opt_outs

  validates :user_id, uniqueness: { scope: :segment_id }
end
