# frozen_string_literal: true

require_relative "manifests/full"
require_relative "manifests/minimal"

module DemoSeed
  # What the demo image carries from outside the production build context
  # (Dockerfile.demo): only the corpus files and spec fixtures the manifests
  # name, not the whole 600 MB corpus. corpus_files.txt is the checked-in list
  # the image build reads without Ruby; spec/seeds/demo_manifest_spec.rb keeps
  # it equal to the manifests, and `bin/rails demo:corpus_files` rewrites it.
  module CorpusFiles
    LIST = Pathname(__dir__).join("corpus_files.txt").freeze

    def self.from_manifests(key = :file)
      found = []
      walk = lambda do |node|
        case node
        when Hash then node.each { |name, value| name == key ? found << value : walk.call(value) }
        when Array then node.each(&walk)
        end
      end
      [ Manifests::FULL, Manifests::MINIMAL ].each(&walk)
      found.uniq.sort
    end

    def self.write! = LIST.write(from_manifests.join("\n") + "\n")
  end
end
