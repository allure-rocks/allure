# frozen_string_literal: true

module Settings
  # Universal settings hub (DESIGN.md §8.5): /settings renders the grouped
  # collection on every breakpoint. Each sub-page keeps its own URL; from md up
  # the shell repeats the collection beside the content, below md it shows a
  # back link to this hub.
  class EntryController < ApplicationController
    def show
    end
  end
end
