# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Auth::Config do
  around do |example|
    previous = ENV.to_h.slice("AUTH_SESSION_IDLE_DAYS", "AUTH_SESSION_MAX_DAYS")
    example.run
  ensure
    %w[AUTH_SESSION_IDLE_DAYS AUTH_SESSION_MAX_DAYS].each { |key| ENV[key] = previous[key] }
  end

  it "defaults to 30 idle days and 90 days at most" do
    ENV.delete("AUTH_SESSION_IDLE_DAYS")
    ENV.delete("AUTH_SESSION_MAX_DAYS")

    expect(described_class.session_idle_timeout).to eq(30.days)
    expect(described_class.session_max_lifetime).to eq(90.days)
  end

  it "reads positive day counts at call time" do
    ENV["AUTH_SESSION_IDLE_DAYS"] = " 7 "
    ENV["AUTH_SESSION_MAX_DAYS"] = "14"

    expect(described_class.session_idle_timeout).to eq(7.days)
    expect(described_class.session_max_lifetime).to eq(14.days)
  end

  it "falls back to the default instead of disabling the limit" do
    ENV["AUTH_SESSION_IDLE_DAYS"] = "0"
    ENV["AUTH_SESSION_MAX_DAYS"] = "forever"

    expect(described_class.session_idle_timeout).to eq(30.days)
    expect(described_class.session_max_lifetime).to eq(90.days)
  end

  it "keeps the re-authentication window at ten minutes" do
    expect(described_class.reauthentication_window).to eq(10.minutes)
  end
end
