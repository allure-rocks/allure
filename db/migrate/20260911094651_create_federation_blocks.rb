class CreateFederationBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :federation_domain_blocks do |t|
      t.string :domain, null: false
      t.text :reason
      t.bigint :created_by_id
      t.timestamps
    end

    add_index :federation_domain_blocks, :domain, unique: true
    add_foreign_key :federation_domain_blocks, :users, column: :created_by_id, on_delete: :nullify
    add_check_constraint :federation_domain_blocks,
                         "char_length(domain) > 0",
                         name: "federation_domain_blocks_domain"

    create_table :federation_actor_blocks do |t|
      t.text :actor_uri, null: false
      t.text :reason
      t.bigint :created_by_id
      t.timestamps
    end

    add_index :federation_actor_blocks, :actor_uri, unique: true
    add_foreign_key :federation_actor_blocks, :users, column: :created_by_id, on_delete: :nullify
    add_check_constraint :federation_actor_blocks,
                         "char_length(actor_uri) > 0",
                         name: "federation_actor_blocks_uri"
  end
end
