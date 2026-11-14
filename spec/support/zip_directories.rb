# frozen_string_literal: true

# A ZIP made of its end records alone, declaring `count` central-directory
# entries it never holds: what a central-directory amplification looks like
# to the entry-count check, built without writing millions of entries.
module ZipDirectoryHelpers
  def zip_declaring(count, comment: "")
    if count > 0xFFFE
      zip64 = [ 0x06064b50, 44, 45, 45, 0, 0, count, count, 0, 0 ].pack("VQ<vvVVQ<Q<Q<Q<")
      locator = [ 0x07064b50, 0, 0, 1 ].pack("VVQ<V")
      eocd = [ 0x06054b50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, comment.bytesize ].pack("VvvvvVVv")
      zip64 + locator + eocd + comment
    else
      [ 0x06054b50, 0, 0, count, count, 0, 0, comment.bytesize ].pack("VvvvvVVv") + comment
    end
  end
end

RSpec.configure do |config|
  config.include ZipDirectoryHelpers
end
