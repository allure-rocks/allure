# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::LoopDetector do
  let(:circuit) do
    [ [ 0.0, 0.0 ], [ 0.002, 0.0 ], [ 0.002, 0.002 ], [ 0.0, 0.002 ], [ 0.0, 0.0 ] ]
  end

  it "returns the first completed circuit" do
    result = described_class.detect(circuit)

    expect(result).to have_attributes(start_index: 0, end_index: 4)
    expect(result.travelled_distance_meters).to be > 400
    expect(result.closure_distance_meters).to eq(0.0)
    expect(result.coordinates).to be_frozen
  end

  it "does not classify a retraced out-and-back as a loop" do
    out_and_back = [ [ 0.0, 0.0 ], [ 0.004, 0.0 ], [ 0.0, 0.0 ] ]

    expect(described_class.detect(out_and_back)).to be_nil
  end

  it "ignores closures shorter than the minimum loop distance" do
    short_circuit = [ [ 0.0, 0.0 ], [ 0.0005, 0.0 ], [ 0.0005, 0.0005 ], [ 0.0, 0.0005 ], [ 0.0, 0.0 ] ]

    expect(described_class.detect(short_circuit)).to be_nil
  end

  describe "the retrace guard" do
    let(:metres_per_degree) { 111_319.49 }

    def east(metres) = metres / metres_per_degree

    def out_and_back(leg_metres, step_metres)
      out = (0..(leg_metres / step_metres)).map { |index| [ east(index * step_metres), 0.0 ] }
      out + out.reverse.drop(1)
    end

    # A square of `side` metres starting and ending at the origin, one point
    # every `step` metres.
    def square(side, step)
      corners = [ [ 0.0, 0.0 ], [ side, 0.0 ], [ side, side ], [ 0.0, side ], [ 0.0, 0.0 ] ]
      corners.each_cons(2).flat_map do |(from_x, from_y), (to_x, to_y)|
        (0...(side / step)).map do |index|
          fraction = index * step / side
          [ east(from_x + ((to_x - from_x) * fraction)), east(from_y + ((to_y - from_y) * fraction)) ]
        end
      end + [ [ 0.0, 0.0 ] ]
    end

    def circling(count, radius_metres)
      Array.new(count) do |index|
        angle = index * 0.4
        [ east(radius_metres * Math.cos(angle)) - east(radius_metres), east(radius_metres * Math.sin(angle)) ]
      end
    end

    it "samples a prefix exactly as the resampler does" do
      points = described_class.normalize_coordinates(square(300.0, 7.0) + out_and_back(500.0, 3.0))
      lengths = Allure::Geometry::Resampler.cumulative_lengths(points)

      [ 1, 2, 17, 170, points.length - 1 ].each do |end_index|
        expected = Allure::Geometry::Resampler.resample(points[0..end_index], count: described_class::RETRACE_SAMPLE_COUNT)

        expect(described_class.prefix_samples(points, lengths, end_index)).to eq(expected)
      end
    end

    it "still finds a loop after an out-and-back and a long stop at the start" do
      stop = Array.new(300) { [ 0.0, 0.0 ] }
      loop_points = square(300.0, 5.0)
      coordinates = out_and_back(1_000.0, 5.0) + stop + loop_points.drop(1)

      result = described_class.detect(coordinates)

      # The square comes back within the closure radius on its last side.
      expect(result.end_index).to be_between(coordinates.length - 7, coordinates.length - 1)
    end

    it "gives up after a bounded number of rejected closures around the start" do
      coordinates = out_and_back(300.0, 5.0) + circling(50_000, 15.0)
      frechet_calls = 0
      distance_calls = 0
      allow(Allure::Geometry::Frechet).to receive(:distance).and_wrap_original do |original, *arguments, **options|
        frechet_calls += 1
        original.call(*arguments, **options)
      end
      allow(Allure::Gpx::Geo).to receive(:horizontal_distance).and_wrap_original do |original, *arguments|
        distance_calls += 1
        original.call(*arguments)
      end

      expect(described_class.detect(coordinates)).to be_nil
      expect(frechet_calls).to eq(described_class::MAX_RETRACE_CHECKS)
      expect(distance_calls).to be < 2_000_000
    end
  end
end
