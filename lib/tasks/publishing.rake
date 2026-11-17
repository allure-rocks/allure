# frozen_string_literal: true

namespace :publishing do
  desc "Verify publication data before a publishing migration"
  task preflight: :environment do
    result = Workouts::PublicationPreflight.new.call

    if result.passed?
      puts "Publication preflight passed (#{result.publication_count} publications checked)."
      next
    end

    result.issues.each do |issue|
      target = [ issue.identifier, issue.resource_id && "id=#{issue.resource_id}" ].compact.join(" ")
      warn "- #{issue.code}: #{target}: #{issue.details}"
    end
    abort "Publication preflight failed; no data was changed."
  end
end
