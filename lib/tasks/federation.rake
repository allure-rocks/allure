# frozen_string_literal: true

namespace :federation do
  desc "Move stored local identities from FROM to the configured FEDERATION_BASE_URL (dry run unless APPLY=1)"
  task rename_host: :environment do
    from = ENV["FROM"].presence or abort "Usage: bin/rails federation:rename_host FROM=https://old.example [APPLY=1]"
    apply = ENV["APPLY"] == "1"
    counts = Federation::HostRename.new(from:).call(apply:)

    counts.each { |table, count| puts "#{table}: #{count}" }
    puts apply ? "Rewritten to #{Allure::Federation.config.base_url}." : "Dry run, nothing changed. Run again with APPLY=1."
  rescue Federation::HostRename::InvalidRename => error
    abort error.message
  end

  desc "End relationships with blocked or deleted remote accounts (dry run unless APPLY=1)"
  task repair_relationships: :environment do
    apply = ENV["APPLY"] == "1"
    findings = Federation::RelationshipRepair.new.call(apply:)

    findings.each do |finding|
      following = finding.following
      puts "#{finding.reason}: #{following.follower_actor.uri} -> #{following.followed_actor.uri} (#{finding.status})"
    end
    verb = apply ? "Ended" : "Would end"
    puts "#{verb} #{findings.size} relationship(s).#{" Run again with APPLY=1 to apply." if !apply && findings.any?}"
  end
end
