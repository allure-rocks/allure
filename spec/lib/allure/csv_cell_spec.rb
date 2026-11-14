# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::CsvCell do
  it "prefixes text starting with a formula character" do
    [ "=1+1", "+cmd", "-2+3", "@SUM(A1)", "\tx", "\rx" ].each do |value|
      expect(described_class.safe(value)).to eq("'#{value}")
    end
  end

  it "leaves numbers, nil and ordinary text alone" do
    [ -5.2, 0, 42, nil, true, "Morning ride", "marie@remote.example", "Col = 2000 m", "2026-08-01T06:00:00Z" ]
      .each { |value| expect(described_class.safe(value)).to eq(value) }
  end

  it "writes a CSV line of safe cells" do
    expect(described_class.line([ "=1+1", -5.2, nil, "a,b" ])).to eq(%('=1+1,-5.2,,"a,b"\n))
  end
end
