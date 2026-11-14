# frozen_string_literal: true

# Federated authorities are DNS names, so their case carries no meaning. The
# code now folds the host everywhere it derives an authority or compares an
# actor URI for blocking; this one-time pass brings the rows written before
# that change onto the same canonical strings, so the rate limiter, the block
# checks, and the source-domain validation all agree.
class NormalizeFederatedAuthorityCase < ActiveRecord::Migration[8.1]
  def up
    normalize_column("federation_inbox_items", "remote_domain")
    normalize_column("remote_notes", "source_domain")
    normalize_column("remote_segments", "source_domain")
    normalize_actor_blocks
  end

  def down
    # Authority case is not meaningful to restore.
  end

  private

  def normalize_column(table, column)
    execute <<~SQL.squish
      UPDATE #{table} SET #{column} = lower(#{column}) WHERE #{column} <> lower(#{column})
    SQL
  end

  # Two blocks that differ only by host case fold onto the same key, which the
  # unique index on actor_uri would refuse; they block the same actor, so the
  # later duplicate is dropped instead of aborting the migration.
  def normalize_actor_blocks
    select_all("SELECT id, actor_uri FROM federation_actor_blocks ORDER BY id").each do |row|
      normalized = normalize_uri(row.fetch("actor_uri"))
      next if normalized == row.fetch("actor_uri")

      id = row.fetch("id").to_i
      if select_value("SELECT 1 FROM federation_actor_blocks WHERE actor_uri = #{quote(normalized)} LIMIT 1")
        execute "DELETE FROM federation_actor_blocks WHERE id = #{id}"
      else
        execute <<~SQL.squish
          UPDATE federation_actor_blocks SET actor_uri = #{quote(normalized)} WHERE id = #{id}
        SQL
      end
    end
  end

  def normalize_uri(value)
    parsed = URI.parse(value.to_s)
    return value.to_s if parsed.host.blank?

    parsed.host = parsed.host.downcase
    parsed.to_s
  rescue URI::InvalidURIError, URI::InvalidComponentError, NoMethodError
    value.to_s
  end
end
