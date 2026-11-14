# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Privacy::EndpointMaskPolicy do
  let(:segments) do
    [
      [ [ 6.4074, 45.0710 ], [ 6.4080, 45.0716 ], [ 6.4086, 45.0722 ] ],
      [ [ 6.4092, 45.0728 ], [ 6.4098, 45.0734 ] ]
    ]
  end

  def zone(longitude, latitude, radius_meters = 100)
    Allure::Federation::Privacy::Zone.new(center: [ longitude, latitude ], radius_meters:)
  end

  it "allows an explicitly unmasked route without zones" do
    expect do
      described_class.new(segments:, zones: [], mask_start: false, mask_finish: false).call
    end.not_to raise_error
  end

  it "requires a zone for the enabled start mask" do
    expect do
      described_class.new(segments:, zones: [], mask_start: true, mask_finish: false).call
    end.to raise_error(described_class::UnsatisfiedEndpoint) { |error| expect(error.endpoint).to eq(:start) }
  end

  it "requires a zone for the enabled finish mask" do
    expect do
      described_class.new(segments:, zones: [], mask_start: false, mask_finish: true).call
    end.to raise_error(described_class::UnsatisfiedEndpoint) { |error| expect(error.endpoint).to eq(:finish) }
  end

  it "checks each endpoint independently" do
    expect do
      described_class.new(
        segments:,
        zones: [ zone(6.4074, 45.0710), zone(6.4098, 45.0734) ],
        mask_start: true,
        mask_finish: true
      ).call
    end.not_to raise_error

    expect do
      described_class.new(
        segments:,
        zones: [ zone(6.4074, 45.0710) ],
        mask_start: true,
        mask_finish: true
      ).call
    end.to raise_error(described_class::UnsatisfiedEndpoint) { |error| expect(error.endpoint).to eq(:finish) }
  end

  it "accepts an endpoint at the zone center" do
    expect do
      described_class.new(
        segments:,
        zones: [ zone(6.4074, 45.0710, 1) ],
        mask_start: true,
        mask_finish: false
      ).call
    end.not_to raise_error
  end

  it "rejects malformed segments" do
    expect do
      described_class.new(segments: [ [ [ 6.4, 45.0 ] ] ], zones: [], mask_start: false, mask_finish: false).call
    end.to raise_error(Allure::Federation::Privacy::ZoneFilter::InvalidInput)
  end
end
