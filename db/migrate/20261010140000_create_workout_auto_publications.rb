# frozen_string_literal: true

# docs/dev/AUTO-PUBLISHING.md: a publishing profile may publish every new import
# by itself, once the workout's enrichments have settled. The profile carries
# the opt-in (off by default, one per audience and account); each import that
# meets an automatic profile leaves one ledger row per audience, which records
# the wait, the outcome and its reason for the owner.
class CreateWorkoutAutoPublications < ActiveRecord::Migration[8.1]
  NOTIFICATION_KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed comment
    import_connection_expired import_connection_revoked
  ].freeze

  def up
    add_column :publishing_profiles, :auto_publish, :boolean, default: false, null: false
    add_column :publishing_profiles, :auto_publish_exclude_commute, :boolean, default: false, null: false
    add_index :publishing_profiles, %i[user_id audience], unique: true, where: "auto_publish",
                                                          name: "index_publishing_profiles_on_user_audience_auto"

    create_table :workout_auto_publications do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :publishing_profile, foreign_key: { on_delete: :nullify }
      t.references :workout_publication, foreign_key: { on_delete: :nullify }
      t.string :audience, null: false
      t.string :status, null: false, default: "waiting"
      t.string :reason
      t.text :detail
      t.datetime :deadline_at, null: false
      t.datetime :settled_at
      t.timestamps

      t.index %i[workout_id audience], unique: true, name: "index_workout_auto_publications_on_workout_audience"
      t.index %i[status deadline_at], name: "index_workout_auto_publications_on_status_deadline"
      t.check_constraint "status IN ('waiting', 'published', 'skipped', 'failed')",
                         name: "workout_auto_publications_status"
      t.check_constraint "audience IN ('public', 'followers')", name: "workout_auto_publications_audience"
      t.check_constraint "(status = 'waiting') = (settled_at IS NULL)", name: "workout_auto_publications_settled"
    end

    add_column :users, :notify_auto_published, :boolean, default: true, null: false
    add_column :users, :notify_auto_publication_failed, :boolean, default: true, null: false

    replace_notification_kinds(NOTIFICATION_KINDS + %w[auto_published auto_publication_failed])
  end

  def down
    replace_notification_kinds(NOTIFICATION_KINDS)
    remove_column :users, :notify_auto_publication_failed
    remove_column :users, :notify_auto_published
    drop_table :workout_auto_publications
    remove_index :publishing_profiles, name: "index_publishing_profiles_on_user_audience_auto"
    remove_column :publishing_profiles, :auto_publish_exclude_commute
    remove_column :publishing_profiles, :auto_publish
  end

  private

  def replace_notification_kinds(kinds)
    remove_check_constraint :notifications, name: "notifications_kind"
    add_check_constraint :notifications,
                         "kind IN (#{kinds.map { |kind| "'#{kind}'" }.join(', ')})",
                         name: "notifications_kind"
  end
end
