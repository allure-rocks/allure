# frozen_string_literal: true

namespace :users do
  desc "Create an Allure user interactively"
  task create: :environment do
    require "io/console"

    print "Username: "
    username = STDIN.gets&.chomp.to_s
    print "Email: "
    email_address = STDIN.gets&.chomp.to_s
    password = STDIN.getpass("Password: ")
    password_confirmation = STDIN.getpass("Password confirmation: ")

    abort "Passwords do not match." unless password == password_confirmation

    user = User.create!(
      username:,
      email_address:,
      password:,
      password_confirmation:
    )

    puts "Created user #{user.username} (#{user.email_address})."
  rescue ActiveRecord::RecordInvalid => error
    abort "User could not be created: #{error.record.errors.full_messages.to_sentence}"
  end

  desc "Generate a single-use registration invitation link (works while registration is closed)"
  task invite: :environment do
    email = ENV["EMAIL"].presence
    if email.nil? && $stdin.tty?
      print "Email: "
      email = STDIN.gets&.chomp
    end
    email = email.to_s.strip.downcase

    abort "EMAIL is required (set EMAIL=... or run interactively)." if email.blank?
    abort "A user with #{email} already exists." if User.exists?(email_address: email)

    days = Integer(ENV.fetch("EXPIRES_IN_DAYS", "7"), exception: false)
    abort "EXPIRES_IN_DAYS must be a positive integer." unless days&.positive?

    invitation, raw_token = RegistrationInvitation.issue(email_address: email, display_name: ENV["NAME"],
                                                         expires_in: days.days)
    link = "#{Allure::Federation.config.base_url}#{Rails.application.routes.url_helpers.new_registration_path(invitation_token: raw_token)}"

    puts "Single-use invitation for #{email}, valid until #{invitation.expires_at.utc.strftime('%Y-%m-%d %H:%M UTC')}:"
    puts link
  rescue ActiveRecord::RecordInvalid => error
    abort "Invitation could not be created: #{error.record.errors.full_messages.to_sentence}"
  end

  desc "Remove every second factor of an account (PLAN_AUTH.md §5.7); it enrols again at its next sign-in"
  task reset_second_factor: :environment do
    username = ENV["USERNAME"].to_s.strip.downcase
    abort "USERNAME is required." if username.blank?

    user = User.find_by(username:)
    abort "No account named #{username}." unless user

    Auth::FactorChanges.reset!(user)
    Admin::Audit.record(actor: nil, action: :second_factor_reset, subject: user,
                        metadata: { "username" => user.username, "source" => "console" })
    puts "Second factors removed for #{user.username}; every session is closed."
  end

  desc "Email a password-less account a one-time link to set a password (PLAN_AUTH.md §6.5)"
  task send_password_setup: :environment do
    username = ENV["USERNAME"].to_s.strip.downcase
    abort "USERNAME is required." if username.blank?

    user = User.find_by(username:)
    abort "No account named #{username}." unless user
    abort "#{user.username} already has a password; use the password reset page." if user.password?

    PasswordsMailer.reset(user).deliver_now
    Admin::Audit.record(actor: nil, action: :password_setup_sent, subject: user,
                        metadata: { "username" => user.username, "source" => "console" })
    puts "Password setup link sent to #{user.username}."
  end
end
