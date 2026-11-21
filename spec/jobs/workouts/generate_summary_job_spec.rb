# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §6: one generation. The provider is WebMock; the facts come
# from the same context the MCP tool serves.
RSpec.describe Workouts::GenerateSummaryJob, :assistant do
  include ActiveJob::TestHelper

  let(:url) { "#{AssistantHelpers::BASE_URL}/v1/chat/completions" }
  let(:user) { create(:user, ai_enabled: true) }
  let(:workout) { create(:workout, user:, started_at: 2.days.ago) }

  def completion(content, model: "qwen")
    {
      "id" => "chatcmpl-spec", "model" => model,
      "choices" => [ { "finish_reason" => "stop", "message" => { "role" => "assistant", "content" => content } } ],
      "usage" => { "prompt_tokens" => 100, "completion_tokens" => 40 }
    }
  end

  def stub_answers(*contents)
    responses = contents.map do |content|
      { status: 200, body: completion(content).to_json, headers: { "Content-Type" => "application/json" } }
    end
    stub_request(:post, url).to_return(*responses)
  end

  def valid_answer
    JSON.generate(
      "title" => "Le tour",
      "sentences" => [
        { "text" => "Vous avez parcouru 250 m en 50 s.", "fact_ids" => %w[baseline:distance baseline:moving_time] },
        { "text" => "Votre vitesse moyenne était de 18,0 km/h.", "fact_ids" => [ "baseline:average" ] }
      ]
    )
  end

  def schedule
    Workouts::SummaryRefresh.schedule(workout)
    clear_enqueued_jobs
  end

  def with_request_options(value)
    previous = ENV["AI_REQUEST_OPTIONS"]
    ENV["AI_REQUEST_OPTIONS"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("AI_REQUEST_OPTIONS") : ENV["AI_REQUEST_OPTIONS"] = previous
  end

  it "writes a verified answer and counts the call" do
    schedule
    stub_answers(valid_answer)

    described_class.perform_now(workout)

    row = workout.reload.assistant_summary
    expect(row).to be_ready
    expect(row.title).to eq("Le tour")
    expect(row.sentences.size).to eq(2)
    expect(row.model).to eq("qwen")
    expect(row.requests_count).to eq(1)
    expect(row.generated_at).to be_present
    expect(row.last_error).to be_nil
  end

  it "asks the provider in the member's voice" do
    schedule
    stub_answers(valid_answer)

    described_class.perform_now(workout)

    expect(a_request(:post, url).with { |request|
      system = JSON.parse(request.body)["messages"].first["content"]
      system.include?('Address the owner as "vous"') && system.include?("a training partner")
    }).to have_been_requested
  end

  it "shows the provider no jargon list and no style example to copy" do
    cycling = create(:workout, user:, sport: catalog_sport("cycling"), started_at: 2.days.ago)
    Workouts::SummaryRefresh.schedule(cycling)
    clear_enqueued_jobs
    stub_answers(valid_answer)

    described_class.perform_now(cycling)

    expect(a_request(:post, url).with { |request|
      system = JSON.parse(request.body)["messages"].first["content"]
      !system.include?("D+, bosse, col") && system.include?("Choose what this outing is about")
    }).to have_been_requested
  end

  it "asks for the answer in the prompt when a thinking mode is configured" do
    with_request_options('{"reasoning_effort":"medium","max_tokens":5000}') do
      schedule
      stub_answers(valid_answer)

      described_class.perform_now(workout)
    end

    expect(a_request(:post, url).with { |request|
      body = JSON.parse(request.body)
      !body.key?("response_format") && body["messages"].first["content"].include?('"fact_ids"')
    }).to have_been_requested
  end

  it "accepts one quiet sentence within the fixed narrative bound" do
    schedule
    # The first workout of a sport holds its records: drop them so the facts
    # carry nothing but the baseline.
    workout.records.delete_all
    quiet = JSON.generate(
      "title" => "Boucle tranquille",
      "sentences" => [ { "text" => "Une sortie sans histoire.", "fact_ids" => [ "baseline:distance" ] } ]
    )
    stub_answers(quiet)

    described_class.perform_now(workout)

    row = workout.reload.assistant_summary
    expect(row).to be_ready
    expect(row.sentences.size).to eq(1)
    expect(a_request(:post, url).with { |request|
      body = JSON.parse(request.body)
      body["temperature"] == 0.7 &&
        body.dig("response_format", "json_schema", "schema", "properties", "sentences", "maxItems") == 3
    }).to have_been_requested
  end

  it "retries once at temperature 0 when a sentence invents a number" do
    schedule
    invented = JSON.generate(
      "title" => "Le tour",
      "sentences" => [
        { "text" => "Vous avez parcouru 300 m.", "fact_ids" => [ "baseline:distance" ] },
        { "text" => "Votre vitesse moyenne était de 99,0 km/h.", "fact_ids" => [ "baseline:average" ] }
      ]
    )
    stub_answers(invented, valid_answer)

    described_class.perform_now(workout)

    row = workout.reload.assistant_summary
    expect(row).to be_ready
    expect(row.requests_count).to eq(2)
    expect(a_request(:post, url).with { |request|
      JSON.parse(request.body)["messages"].last["content"].include?("previous answer was refused")
    }).to have_been_requested
  end

  it "fails invalid after the second refused answer" do
    schedule
    invented = JSON.generate(
      "title" => "Le tour",
      "sentences" => [
        { "text" => "Vous avez parcouru 300 m.", "fact_ids" => [ "baseline:distance" ] },
        { "text" => "Votre vitesse moyenne était de 99,0 km/h.", "fact_ids" => [ "baseline:average" ] }
      ]
    )
    stub_answers(invented, invented)

    described_class.perform_now(workout)

    row = workout.reload.assistant_summary
    expect(row).to be_failed
    expect(row.last_error).to eq("invalid")
    expect(row.requests_count).to eq(2)
  end

  it "fails rejected on a terminal provider rejection" do
    schedule
    stub_request(:post, url).to_return(
      status: 401, body: { "error" => { "message" => "Invalid API key" } }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.perform_now(workout)

    expect(workout.reload.assistant_summary).to be_failed
    expect(workout.assistant_summary.last_error).to eq("rejected")
  end

  it "deletes a pending row whose owner withdrew consent" do
    schedule
    user.update!(ai_enabled: false)

    described_class.perform_now(workout)

    expect(WorkoutSummary.exists?(workout_id: workout.id)).to be(false)
  end

  it "waits when the day's budget is spent and leaves the row pending" do
    schedule
    ENV["AI_MAX_REQUESTS_PER_DAY"] = "1"
    create(:workout_summary, workout: create(:workout), requests_count: 1)

    expect { described_class.perform_now(workout) }.to have_enqueued_job(described_class)
    expect(workout.reload.assistant_summary).to be_pending
  end

  it "does nothing when the row already matches the facts" do
    schedule
    row = workout.reload.assistant_summary
    snapshot = Workouts::SummaryFacts.new(workout).call
    row.update!(status: "ready", facts_digest: snapshot.digest, version: Allure::Insights::VERSION)

    described_class.perform_now(workout)

    expect(row.reload).to be_ready
    expect(a_request(:post, url)).not_to have_been_requested
  end
end
