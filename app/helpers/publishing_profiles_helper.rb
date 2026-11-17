# frozen_string_literal: true

module PublishingProfilesHelper
  def publishing_profile_metric_label(metric)
    t("publishing_profiles.settings.metrics.#{metric}")
  end

  # The publishing-delay presets (docs/dev/DELAYED-PUBLISHING.md), shared by the
  # profile form, the publish form, and the scheduled card. `immediate` is
  # omitted where the action already means "publish now" — the scheduled card's
  # reschedule select has its own Publish now button.
  def publishing_delay_options(include_immediate: true)
    delays = PublishingProfile::PUBLISH_DELAYS
    delays = delays.except("immediate") unless include_immediate
    delays.map do |key, seconds|
      [ t("publishing_profiles.delays.#{key}"), seconds ]
    end
  end

  # "without delay" / "after a 1 day delay", for the automatic-publishing
  # notices (docs/dev/AUTO-PUBLISHING.md).
  def auto_publish_delay_phrase(profile)
    return t("publishing_profiles.auto_notice.immediate") if profile.publish_delay_seconds.zero?

    t("publishing_profiles.auto_notice.delayed", delay: publishing_delay_label(profile.publish_delay_seconds))
  end

  # The sports an automatic profile leaves out, in display order, or nil when
  # it excludes none. Joined by a comma rather than `to_sentence`, whose
  # connectors this application does not translate.
  def auto_publish_excluded_sports_names(profile)
    slugs = profile.auto_publish_excluded_sports
    return if slugs.empty?

    Sport.alphabetical(Sport.where(slug: slugs)).map { sport_display_name(it) }.join(", ")
  end

  # DESIGN.md §19.13: who a followers publication reaches. Local followers
  # always; approved instances only while restricted federation is enabled.
  def followers_reach_notice
    key = if !Allure::Federation::Config.enabled?
      "local"
    elsif Allure::Federation::Config.restricted_enabled?
      "federated"
    else
      "not_federated"
    end
    t("publishing_profiles.followers_reach.#{key}")
  end

  def publishing_delay_label(seconds)
    key = PublishingProfile::PUBLISH_DELAYS.key(seconds) || "immediate"
    t("publishing_profiles.delays.#{key}")
  end
end
