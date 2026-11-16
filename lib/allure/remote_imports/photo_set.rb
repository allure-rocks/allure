# frozen_string_literal: true

module Allure
  module RemoteImports
    # The photos of one activity (docs/dev/REMOTE-IMPORTS.md): how many the
    # provider announced (`listed`) and the ones it could download. A provider
    # without photos returns `PhotoSet.new`, and a photo whose download failed
    # is counted as missing rather than failing the activity.
    PhotoSet = Data.define(:listed, :photos) do
      def initialize(listed: 0, photos: []) = super
    end
  end
end
