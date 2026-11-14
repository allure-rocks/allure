# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Solid Cable configuration" do
  it "uses the dedicated cable database in production without Redis" do
    production = Rails.application.config_for(:cable, env: "production")

    expect(production.fetch(:adapter)).to eq("solid_cable")
    expect(production.dig(:connects_to, :database, :writing)).to eq("cable")
    expect(production.to_s).not_to include("redis")
  end

  it "ships the generated Solid Cable schema" do
    schema = Rails.root.join("db/cable_schema.rb").read
    expect(schema).to include('create_table "solid_cable_messages"')
  end
end
