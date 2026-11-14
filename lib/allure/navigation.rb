# frozen_string_literal: true

module Allure
  # A tiny DSL backing config/navigation.rb.
  #
  # Deliberately minimal: it builds an immutable tree of plain structs at boot,
  # and knows nothing about rendering. Resolving paths and deciding what is
  # visible is the view layer's job (see NavigationHelper), because both need
  # request context that does not exist at load time.
  module Navigation
    Item = Struct.new(:key, :icon, :path, :policy, :items, keyword_init: true) do
      def leaf? = items.empty?
    end

    Section = Struct.new(:key, :position, :items, keyword_init: true)

    class << self
      def define(&block)
        @sections = []
        Builder.new(self).instance_eval(&block)
        @sections.freeze
      end

      def sections(position: :top)
        (@sections || []).select { it.position == position }
      end

      def reset! = @sections = []

      def add_section(section) = (@sections << section)
    end

    class Builder
      def initialize(registry) = @registry = registry

      def section(key, position: :top, &block)
        items = ItemBuilder.new.tap { it.instance_eval(&block) }.items
        @registry.add_section(Section.new(key:, position:, items: items.freeze))
      end
    end

    class ItemBuilder
      attr_reader :items

      def initialize = @items = []

      def item(key, icon:, path: nil, policy: nil, &block)
        children = block ? ItemBuilder.new.tap { it.instance_eval(&block) }.items : []
        @items << Item.new(key:, icon:, path:, policy:, items: children.freeze)
      end
    end
  end
end
