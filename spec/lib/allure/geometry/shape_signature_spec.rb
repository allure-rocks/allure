# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::ShapeSignature do
  it "returns 64 finite values for a straight line" do
    signature = described_class.compute([ [ 0.0, 0.0 ], [ 0.01, 0.0 ] ])

    expect(signature.length).to eq(64)
    expect(signature).to all(be_finite)
    expect(signature).to all(eq(0.0))
  end

  it "is stable when the same shape has a denser input" do
    coarse = [ [ 0.0, 0.0 ], [ 0.005, 0.002 ], [ 0.01, 0.0 ] ]
    dense = [ [ 0.0, 0.0 ], [ 0.0025, 0.001 ], [ 0.005, 0.002 ], [ 0.0075, 0.001 ], [ 0.01, 0.0 ] ]

    expect(described_class.compute(dense)).to eq(described_class.compute(coarse))
  end

  it "documents the intentional rotation-invariance collision" do
    original = [ [ 0.0, 0.0 ], [ 0.01, 0.0 ], [ 0.01, 0.01 ] ]
    rotated = [ [ 0.0, 0.0 ], [ 0.0, 0.01 ], [ -0.01, 0.01 ] ]

    expect(described_class.compute(rotated)).to eq(described_class.compute(original))
  end
end
