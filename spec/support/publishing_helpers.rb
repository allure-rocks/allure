# frozen_string_literal: true

module PublishingHelpers
  # The account's built-in public profile, created once and reused. The
  # built-in key is unique per account, so two publications for the same
  # account must share one profile row rather than each creating one.
  def public_publishing_profile_for(user)
    PublishingProfile.ensure_built_ins_for!(user)
    user.publishing_profiles.find_by!(built_in_key: "public")
  end

  # Publishes through the real scheduling path, then activates synchronously.
  # Most specs assert on the shared representation, not the safety delay
  # itself; the delay has dedicated coverage in the pure service specs.
  def publish_workout!(user:, workout:, profile:, delay: nil)
    publication = Workouts::Publisher.new(user:, workout:, profile:, delay:).call!
    Workouts::ScheduledPublicationActivation.new(publication:, force: true).call!
    publication
  end
end

RSpec.configure do |config|
  config.include PublishingHelpers
end
