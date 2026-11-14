# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ShortId do
  VECTORS = {
    "00000000-0000-0000-0000-000000000000" => "2222222222222222222222",
    "00000000-0000-0000-0000-000000000001" => "2222222222222222222223",
    "550e8400-e29b-41d4-a716-446655440000" => "H9cNmGXLEc8NWcZzSThA9S",
    "ffffffff-ffff-ffff-ffff-ffffffffffff" => "oZEq7ovRbLq6UnGMPwc8B5"
  }.freeze

  it "matches the permanent Python shortuuid vectors" do
    VECTORS.each do |uuid, short_id|
      expect(described_class.encode(uuid)).to eq(short_id)
      expect(described_class.decode(short_id)).to eq(uuid)
    end
  end

  it "round trips UUIDs" do
    uuid = SecureRandom.uuid
    expect(described_class.decode(described_class.encode(uuid))).to eq(uuid)
  end

  it "rejects malformed UUIDs" do
    expect { described_class.encode("not-a-uuid") }.to raise_error(ArgumentError)
  end

  it "rejects malformed and overflowing ShortUUIDs" do
    invalid = [ "short", "0" * 22, "z" * 22 ]
    invalid.each { |value| expect { described_class.decode(value) }.to raise_error(ArgumentError) }
  end
end
