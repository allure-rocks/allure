# frozen_string_literal: true

# The operator audit log: one immutable row per administrative mutation, so a
# self-hosted instance can answer who blocked a domain, took down a
# publication, suspended an account, or retried a job.
class CreateAdminEvents < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed
    publication_withdrawn
    account_suspended account_reinstated
    invitation_created invitation_revoked
  ].freeze

  def change
    create_table :admin_events do |t|
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :admin_events, %i[subject_type subject_id]
    add_index :admin_events, :action
    add_check_constraint :admin_events,
                         "action::text = ANY (ARRAY[#{ACTIONS.map { |a| "'#{a}'::character varying" }.join(', ')}]::text[])",
                         name: "admin_events_action"
    add_check_constraint :admin_events, "jsonb_typeof(metadata) = 'object'",
                         name: "admin_events_metadata_object"
  end
end
