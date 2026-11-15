# frozen_string_literal: true

# Publishing is immediate by default again: the safety delay is an opt-in
# profile policy (docs/dev/DELAYED-PUBLISHING.md). `0` means "publish now" and is
# the default for new profiles; existing profiles are moved to it because the
# delayed feature has not shipped. The check constraint must admit 0 before the
# default and the backfill are written.
class DefaultImmediatePublishingDelay < ActiveRecord::Migration[8.1]
  DELAY_VALUES = [ 0, 86_400, 259_200, 604_800, 1_209_600, 2_592_000 ].freeze

  def up
    remove_check_constraint :publishing_profiles, name: "publishing_profiles_publish_delay_seconds"
    add_check_constraint :publishing_profiles,
                         "publish_delay_seconds IN (#{DELAY_VALUES.join(', ')})",
                         name: "publishing_profiles_publish_delay_seconds"

    change_column_default :publishing_profiles, :publish_delay_seconds, from: 86_400, to: 0
    execute "UPDATE publishing_profiles SET publish_delay_seconds = 0 WHERE publish_delay_seconds <> 0"
  end

  def down
    execute "UPDATE publishing_profiles SET publish_delay_seconds = 86400 WHERE publish_delay_seconds = 0"

    remove_check_constraint :publishing_profiles, name: "publishing_profiles_publish_delay_seconds"
    add_check_constraint :publishing_profiles,
                         "publish_delay_seconds IN (#{(DELAY_VALUES - [ 0 ]).join(', ')})",
                         name: "publishing_profiles_publish_delay_seconds"

    change_column_default :publishing_profiles, :publish_delay_seconds, from: 0, to: 86_400
  end
end
