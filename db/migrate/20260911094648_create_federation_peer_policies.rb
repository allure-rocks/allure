class CreateFederationPeerPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :federation_peer_policies do |t|
      t.string :domain, null: false
      t.string :capability_profile, null: false, default: "unknown"
      t.text :reason
      t.bigint :approved_by_id
      t.timestamps
    end

    add_index :federation_peer_policies, :domain, unique: true
    add_foreign_key :federation_peer_policies, :users, column: :approved_by_id, on_delete: :nullify
    add_check_constraint :federation_peer_policies,
                         "char_length(domain) > 0",
                         name: "federation_peer_policies_domain"
    add_check_constraint :federation_peer_policies,
                         "capability_profile IN ('unknown', 'public_only', 'restricted_fetch', 'restricted_shared_inbox')",
                         name: "federation_peer_policies_capability"
  end
end
