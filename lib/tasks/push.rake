# frozen_string_literal: true

namespace :push do
  desc "Print a fresh VAPID key pair for push notifications (docs/dev/PUSH.md)"
  task vapid_keys: :environment do
    pair = Allure::Push::Config.generate_key_pair
    puts "VAPID_PUBLIC_KEY=#{pair[:public_key]}"
    puts "VAPID_PRIVATE_KEY=#{pair[:private_key]}"
  end
end
