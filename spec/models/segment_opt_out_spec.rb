# frozen_string_literal: true

require "rails_helper"

RSpec.describe SegmentOptOut do
  let(:segment) { create(:segment) }

  it "is unique per (segment, athlete)" do
    create(:segment_opt_out, segment:, user: segment.user)
    duplicate = build(:segment_opt_out, segment:, user: segment.user)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to be_present
  end

  it "lets the segment owner hold an exclusion row" do
    exclusion = build(:segment_opt_out, segment:, user: segment.user)

    expect(exclusion).to be_valid
  end
end
