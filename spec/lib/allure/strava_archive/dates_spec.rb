# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::StravaArchive::Dates do
  {
    "Aug 31, 2014, 10:54:43 AM" => Time.utc(2014, 8, 31, 10, 54, 43),
    "Aug 31, 2014, 12:48:49 PM" => Time.utc(2014, 8, 31, 12, 48, 49),
    "Sep 1, 2014, 12:05:00 AM" => Time.utc(2014, 9, 1, 0, 5, 0),
    "Mar 3, 2019, 6:00:00\u202FPM" => Time.utc(2019, 3, 3, 18, 0, 0),
    "09.12.2022, 15:24:49" => Time.utc(2022, 12, 9, 15, 24, 49),
    "9 déc. 2022, 15:24:49" => Time.utc(2022, 12, 9, 15, 24, 49),
    "9 juil. 2022 à 07:05:00" => Time.utc(2022, 7, 9, 7, 5, 0),
    "9. Dez. 2022, 15:24:49" => Time.utc(2022, 12, 9, 15, 24, 49),
    "9 de dic. de 2022, 15:24:49" => Time.utc(2022, 12, 9, 15, 24, 49),
    "9 mrt 2022 15:24:49" => Time.utc(2022, 3, 9, 15, 24, 49),
    "09/12/2022 15:24:49" => Time.utc(2022, 12, 9, 15, 24, 49),
    "2022-12-09 15:24:49" => Time.utc(2022, 12, 9, 15, 24, 49),
    "2022年12月9日 下午3:24:49" => Time.utc(2022, 12, 9, 15, 24, 49)
  }.each do |value, expected|
    it "reads #{value.inspect}" do
      expect(described_class.parse(value)).to eq(expected)
    end
  end

  it "returns nil rather than guessing" do
    expect(described_class.parse("")).to be_nil
    expect(described_class.parse("yesterday")).to be_nil
    expect(described_class.parse("31.02.2022, 10:00:00")).to be_nil
  end
end
