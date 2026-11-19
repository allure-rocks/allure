# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/demo/accounts")

RSpec.describe DemoSeed::Accounts do
  it "finds an account by username so a re-seed can reassign its address" do
    user = create(:user, username: "marie", email_address: "marie@demo.allure.rocks")

    found = described_class.find_or_initialize(username: "marie", email: "marie@allure.test")

    expect(found).to eq(user)
    expect(found).to be_persisted
  end

  it "finds an account by address on a database that knows it under that key" do
    user = create(:user, username: "other", email_address: "marie@allure.test")

    expect(described_class.find_or_initialize(username: "marie", email: "marie@allure.test")).to eq(user)
  end

  it "initializes an unknown account with its address" do
    found = described_class.find_or_initialize(username: "marie", email: "marie@allure.test")

    expect(found).to be_new_record
    expect(found.email_address).to eq("marie@allure.test")
  end
end
