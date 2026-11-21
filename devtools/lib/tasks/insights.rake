# frozen_string_literal: true

# Development-only preview of the assistant summary (docs/dev/AI.md §3–§4):
# the facts Ruby computed, the prompt the model receives and, with CALL=1, the
# answer and what the verifier kept. It writes nothing.
#
#   dip rails dev_tools:insights_preview ACCOUNT=marie LIMIT=5
#   dip rails dev_tools:insights_preview ACCOUNT=marie LIMIT=3 CALL=1
#   dip rails dev_tools:insights_preview ACCOUNT=marie ID=71 CALL=1
module DevTools
  class InsightsPreview
    def initialize(account:, limit:, call_model:, workout_id: nil)
      @account = account
      @limit = limit
      @call_model = call_model
      @workout_id = workout_id
    end

    def call
      workouts.each do |workout|
        preview(workout)
        puts
      end
    end

    private

    attr_reader :account, :limit, :call_model, :workout_id

    def user = @user ||= User.find_by(username: account) || abort("No account named #{account}")

    def workouts
      scope = user.workouts.where(origin: "import").where("analysis_version > 0")
      scope = scope.where(id: workout_id) if workout_id
      scope = scope.order(started_at: :desc).limit(limit)
      abort "No analysable workout for @#{account}" if scope.empty?

      scope.to_a
    end

    def client
      return @client if defined?(@client)

      @client = call_model ? Allure::Assistant::Config.client : nil
      abort "Set AI_BASE_URL and AI_MODEL to call the model" if call_model && !Allure::Assistant::Config.enabled?
      @client
    end

    def preview(workout)
      snapshot = Workouts::SummaryFacts.new(workout).call
      prompt = Allure::Insights::Prompt.new(facts: snapshot.facts, locale: snapshot.locale,
                                            sport: snapshot.sport_slug)

      puts "=" * 78
      puts "##{workout.id} #{workout.title} — #{workout.sport.slug} — #{workout.started_at}"
      puts "facts: #{snapshot.facts.size} · sentences: #{prompt.sentence_range}"
      puts
      snapshot.facts.each do |fact|
        puts format("%-34s %-10s %-8s %3d  %s", fact.id, fact.kind, fact.sentiment, fact.weight,
                    fact.display)
      end
      print_course(snapshot.course)
      puts
      puts "--- system ---"
      puts prompt.system
      puts "--- user ---"
      puts prompt.user
      answer(prompt, snapshot) if client
    end

    def print_course(course)
      return unless course

      puts
      puts "course: #{course.mode} · #{course.sections.length} sections · #{course.result.distance.round} m"
      course.pairs.each_with_index do |(slot, section), index|
        puts format("  %d %-8s %s", index + 1, slot.terrain, section_line(section))
      end
    end

    def section_line(section)
      parts = [ "#{section.start_distance.round}–#{section.end_distance.round} m",
                "#{section.distance.round} m", "#{section.moving_time.round} s",
                "up #{section.ascent.round} m", "down #{section.descent.round} m",
                "ele #{format('%.0f', section.elevation_coverage * 100)}%" ]
      parts << "hr #{section.heart_rate}" if section.heart_rate
      parts << "gap #{section.grade_adjusted_pace.round} s/km" if section.grade_adjusted_pace
      parts.join(" ")
    end

    def answer(prompt, snapshot)
      result = client.complete(
        system: prompt.system, user: prompt.user,
        schema: Allure::Insights::SummarySchema.call(max_sentences: prompt.max_sentences),
        schema_name: Allure::Insights::Prompt::SCHEMA_NAME,
        temperature: Workouts::SummaryGeneration::TEMPERATURE
      )
      verified = Allure::Insights::Verifier.new(snapshot.facts, max_sentences: prompt.max_sentences)
                                               .call(parse(result.content))

      puts "--- answer (#{result.model}, #{result.calls} call(s), prompt-only: #{result.prompt_only?}) ---"
      puts result.content
      puts "--- verified ---"
      puts "title: #{verified.title.inspect}"
      verified.sentences.each { |row| puts "• #{row["text"]} [#{row["fact_ids"].join(", ")}]" }
      puts "refused: #{verified.refused_sentences.map { it["text"] }.inspect}" if verified.refused_sentences.any?
      puts "valid: #{verified.valid?}"
    end

    def parse(content)
      JSON.parse(content.to_s)
    rescue JSON::ParserError
      nil
    end
  end
end

namespace :dev_tools do
  desc "Print the assistant facts and prompt of an account's latest workouts (CALL=1 calls the model)"
  task insights_preview: :environment do
    abort "dev_tools:insights_preview only exists in development and test" unless Rails.env.local?

    account = ENV["ACCOUNT"].presence || abort("ACCOUNT=<username> is required")
    DevTools::InsightsPreview.new(
      account:,
      limit: (ENV["LIMIT"].presence || 5).to_i,
      call_model: ActiveModel::Type::Boolean.new.cast(ENV["CALL"]),
      workout_id: ENV["ID"].presence&.to_i
    ).call
  end
end
