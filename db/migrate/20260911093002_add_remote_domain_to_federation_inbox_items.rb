class AddRemoteDomainToFederationInboxItems < ActiveRecord::Migration[8.1]
  class InboxItem < ActiveRecord::Base
    self.table_name = "federation_inbox_items"
  end

  def up
    add_column :federation_inbox_items, :remote_domain, :string

    InboxItem.reset_column_information
    InboxItem.where(remote_domain: nil).find_each do |item|
      domain = remote_domain_for(item.actor_uri)
      item.update_columns(remote_domain: domain) if domain
    end

    remaining = InboxItem.where("remote_domain IS NULL OR remote_domain = ''").count
    if remaining.positive?
      raise ActiveRecord::MigrationError,
            "Cannot set federation_inbox_items.remote_domain: " \
            "#{remaining} row(s) have no parsable actor_uri"
    end

    change_column_null :federation_inbox_items, :remote_domain, false
    add_index :federation_inbox_items, [ :remote_domain, :created_at ]
  end

  def down
    remove_index :federation_inbox_items, [ :remote_domain, :created_at ]
    remove_column :federation_inbox_items, :remote_domain
  end

  private

  def remote_domain_for(value)
    parsed = URI.parse(value.to_s)
    return if parsed.host.blank?

    default_port = parsed.scheme == "https" ? 443 : 80
    parsed.port == default_port ? parsed.host : "#{parsed.host}:#{parsed.port}"
  rescue URI::InvalidURIError, URI::InvalidComponentError
    nil
  end
end
