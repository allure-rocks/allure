# frozen_string_literal: true

require "digest"

module Allure
  module Avatar
    # Deterministic generated-avatar art (DESIGN.md §9.2): a pure function of
    # the persisted seed, so an account keeps the same avatar everywhere, on
    # every page and in every process. The recipe is rendered as inline SVG by
    # the view — never a generated image file — and it carries no initials:
    # the adjacent account name is the identifier, the art is decorative.
    #
    # Randomness is derived from SHA-256 bytes, not Ruby's Random, so the art
    # survives Ruby upgrades unchanged.
    class Generator
      MOTIFS = %i[orbit bands dots rings petals].freeze
      DIGEST_BYTES = 32

      def initialize(seed:, palette: Palette::COLOURS, accents: Palette::ACCENTS)
        @seed = seed.to_s
        @palette = palette
        @accents = accents
      end

      def call
        {
          background: pick(@palette, 0),
          shapes: motif
        }
      end

      private

      def motif
        case MOTIFS[byte(1) % MOTIFS.size]
        when :orbit then orbit
        when :bands then bands
        when :dots then dots
        when :rings then rings
        else petals
        end
      end

      def digest = @digest ||= Digest::SHA256.digest(@seed)
      def byte(index) = digest.getbyte(index % DIGEST_BYTES)
      def pick(array, index) = array[byte(index) % array.size]
      def range(min, max, index) = min + (byte(index) % (max - min + 1))
      def opacity(index, base) = [ base + (byte(index) % 4) * 0.08, 0.95 ].min.round(2)

      def circle(cx:, cy:, r:, fill:, opacity:, stroke: nil, stroke_width: nil)
        {
          kind: :circle, cx:, cy:, r:, fill:, opacity:,
          stroke:, stroke_width:
        }.compact
      end

      def orbit
        [
          circle(cx: range(10, 60, 3), cy: range(10, 60, 4), r: range(26, 44, 5),
                 fill: pick(@accents, 6), opacity: opacity(7, 0.5)),
          circle(cx: range(20, 80, 9), cy: range(20, 80, 10), r: range(12, 26, 11),
                 fill: pick(@accents, 12), opacity: opacity(13, 0.65)),
          circle(cx: range(25, 85, 15), cy: range(15, 75, 16), r: range(4, 10, 17),
                 fill: pick(@accents, 18), opacity: opacity(19, 0.85))
        ]
      end

      def bands
        base = range(-25, 10, 2)
        (0..3).map do |i|
          {
            kind: :rect, x: -20, y: base + i * 26, width: 140, height: range(6, 15, 3 + i),
            fill: pick(@accents, 12 + i), opacity: opacity(16 + i, 0.45),
            transform: "rotate(#{range(-18, 18, 8 + i)} 50 50)"
          }
        end
      end

      def dots
        (0..2).flat_map do |row|
          (0..2).map do |col|
            index = 2 + row * 3 + col
            circle(cx: 22 + col * 28 + range(-5, 5, index),
                   cy: 22 + row * 28 + range(-5, 5, index + 9),
                   r: range(5, 11, index + 18),
                   fill: pick(@accents, index), opacity: opacity(index + 27, 0.45))
          end
        end
      end

      def rings
        cx = range(30, 70, 2)
        cy = range(30, 70, 3)
        (0..3).map do |i|
          circle(cx:, cy:, r: 10 + i * 10 + range(0, 4, 4 + i), fill: "none",
                 stroke: pick(@accents, 9 + i), stroke_width: range(3, 7, 14 + i),
                 opacity: opacity(20 + i, 0.55))
        end
      end

      def petals
        cx = range(38, 62, 2)
        cy = range(38, 62, 3)
        (0..3).map do |i|
          {
            kind: :ellipse, cx:, cy:, rx: range(16, 24, 4 + i), ry: range(5, 9, 9 + i),
            fill: pick(@accents, 14 + i), opacity: opacity(24 + i, 0.5),
            transform: "rotate(#{i * 45 + range(-8, 8, 19 + i)} 50 50)"
          }
        end
      end
    end
  end
end
