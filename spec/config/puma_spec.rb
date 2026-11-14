# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/puma.rb" do
  it "lets through the largest body an endpoint accepts, and no more" do
    source = Rails.root.join("config/puma.rb").read
    limit = source[/^http_content_length_limit ([\d_]+)$/, 1]

    expect(limit).to be_present
    expect(Integer(limit.delete("_"), 10)).to eq(Allure::RequestBodyLimit.max_bytes)
  end
end
