# frozen_string_literal: true

# The end of a Strava archive import (PLAN_STRAVA_ARCHIVE.md §8): a whole
# history takes minutes to import and hours to enrich, so the account is told
# by mail when its archive is done, or why it failed. No other import mails.
# Localized to the account, since the mail is queued.
class ImportMailer < ApplicationMailer
  def strava_archive_finished(batch)
    @user = batch.user
    @batch = batch
    I18n.with_locale(@user.locale) do
      @photos = photo_counts
      mail subject: I18n.t("import_mailer.strava_archive_finished.#{batch.status}.subject"), to: @user.email_address
    end
  end

  private

  def photo_counts
    counts = %w[photos photos_missing photos_refused].index_with do |key|
      @batch.entries.sum { |entry| entry.metadata[key].to_i }
    end
    counts.values.any?(&:positive?) ? counts : nil
  end
end
