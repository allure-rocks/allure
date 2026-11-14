# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Categories do
  def row(user_id, category)
    Struct.new(:user_id, :user).new(user_id, Struct.new(:leaderboard_category).new(category))
  end

  it "accepts only the declared filters" do
    expect(described_class.filter?("women")).to be(true)
    expect(described_class.filter?("men")).to be(true)
    expect(described_class.filter?("unspecified")).to be(false)
    expect(described_class.filter?(nil)).to be(false)
  end

  it "keeps the ranking order and only the athletes of the category" do
    rows = [ row(1, "women"), row(2, "men"), row(3, "women"), row(4, "unspecified"), row(5, "women") ]

    expect(described_class.ranking(rows, "women").map(&:user_id)).to eq([ 1, 3, 5 ])
  end

  it "offers a category only from three distinct athletes" do
    rows = [ row(1, "women"), row(2, "women"), row(3, "men") ]

    expect(described_class.ranking(rows, "women")).to be_nil
    expect(described_class.offered?(rows, "women")).to be(false)

    rows << row(4, "women")
    expect(described_class.offered?(rows, "women")).to be(true)
    expect(described_class.offered?(rows, "men")).to be(false)
  end

  it "counts athletes, not rows" do
    rows = [ row(1, "men"), row(1, "men"), row(2, "men") ]

    expect(described_class.offered?(rows, "men")).to be(false)
  end
end
