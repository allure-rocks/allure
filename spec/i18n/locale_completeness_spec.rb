# frozen_string_literal: true

require "rails_helper"

# Every locale carries the same keys, the same interpolation variables and the
# same help pages (DESIGN.md §3.5). French and English are the reference: a key
# either defines is owed by every other locale.
RSpec.describe "Locale completeness" do # rubocop:disable RSpec/DescribeClass
  roots = {
    "application" => Rails.root.join("config/locales"),
    "devtools" => Rails.root.join("devtools/config/locales")
  }.freeze
  reference_locales = %w[fr en].freeze
  variable = /%\{(\w+)\}/

  flatten = lambda do |hash, prefix = nil|
    hash.each_with_object({}) do |(key, value), flat|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flat.merge!(flatten.call(value, path)) : flat[path] = value
    end
  end

  load_locale = lambda do |root, locale|
    path = root.join("#{locale}.yml")
    raise "#{path.relative_path_from(Rails.root)} is missing" unless path.exist?

    document = YAML.load_file(path, aliases: true)
    raise "#{path.relative_path_from(Rails.root)} must have the single root #{locale}" unless document.keys == [ locale ]

    flatten.call(document.fetch(locale))
  end

  variables = ->(value) { Array(value).flat_map { it.to_s.scan(variable).flatten }.uniq.sort }

  it "declares exactly the account locales as available" do
    expect(I18n.available_locales.map(&:to_s)).to match_array(User::LOCALES)
  end

  roots.each do |name, root|
    context "with the #{name} locale files" do
      reference = reference_locales.flat_map { load_locale.call(root, it).keys }.uniq

      User::LOCALES.each do |locale|
        it "gives #{locale} every key and nothing more" do
          keys = load_locale.call(root, locale).keys
          # English inherits the Rails defaults French translates (datetime).
          missing = (reference - keys).reject { locale == "en" && I18n.exists?(it, :en) }

          expect(missing: missing.sort, extra: (keys - reference).sort).to eq(missing: [], extra: [])
        end

        next if locale == "en"

        it "keeps the English interpolation variables in #{locale}" do
          english = load_locale.call(root, "en")
          translated = load_locale.call(root, locale)
          mismatches = english.filter_map do |key, value|
            next unless translated.key?(key)
            next if variables.call(value) == variables.call(translated[key])

            "#{key}: #{variables.call(value).inspect} vs #{variables.call(translated[key]).inspect}"
          end

          expect(mismatches).to eq([])
        end

        it "keeps the English list lengths in #{locale}" do
          english = load_locale.call(root, "en")
          translated = load_locale.call(root, locale)
          mismatches = english.filter_map do |key, value|
            key if value.is_a?(Array) && translated[key].is_a?(Array) && value.size != translated[key].size
          end

          expect(mismatches).to eq([])
        end
      end
    end
  end

  it "has a help page for every topic in every locale" do
    missing = HelpController::TOPICS.values.uniq.product(User::LOCALES).filter_map do |topic, locale|
      path = "app/views/help/topics/_#{topic}.#{locale}.html.erb"
      path unless Rails.root.join(path).exist?
    end

    expect(missing).to eq([])
  end
end
