# frozen_string_literal: true

module Allure
  module Xml
    # Lazily skips a leading UTF-8 BOM and the XML whitespace real exporters
    # sometimes write before the declaration. Nokogiri treats a declaration
    # preceded by whitespace as a *fatal* error, so such a file would be
    # rejected as malformed even though its markup is valid.
    #
    # Only the prologue is removed: the underlying IO is still read in chunks
    # (Nokogiri's pull reader only calls `read(Integer)`), so the streaming
    # parse and its point limits are preserved, and a document that starts with
    # anything but a BOM or whitespace still fails as malformed.
    class SanitizedSource
      BOM = "\xEF\xBB\xBF".b
      READ_SIZE = 4096
      PROLOGUE_PATTERN = /\A[ \t\r\n]*\z/

      def initialize(io)
        @io = io
        @primed = false
        @buffer = nil
      end

      def read(length = nil)
        return read_all if length.nil?

        prime unless @primed
        if @buffer && !@buffer.empty?
          chunk = @buffer.byteslice(0, length)
          @buffer = @buffer.byteslice(chunk.bytesize..) || +""
          chunk
        else
          @io.read(length)
        end
      end

      def eof?
        prime unless @primed
        (@buffer.nil? || @buffer.empty?) && @io.eof?
      end

      def close = @io.close

      private

      def read_all
        prime unless @primed
        rest = @buffer || +""
        @buffer = +""
        rest << @io.read.to_s.b
        rest.empty? ? nil : rest
      end

      def prime
        @primed = true
        head = @io.read(READ_SIZE) || +""
        head = head.b
        head = head.byteslice(BOM.bytesize..) || +"" if head.start_with?(BOM)
        head << (@io.read(READ_SIZE) || +"").b while head.match?(PROLOGUE_PATTERN) && !@io.eof?
        @buffer = head.sub(/\A[ \t\r\n]+/, "")
      end
    end
  end
end
