# frozen_string_literal: true

require "rails_helper"
require_relative "../../../devtools/lib/dev_tools/insights_comparison"

RSpec.describe DevTools::InsightsComparison, :assistant do
  let(:user) { create(:user, ai_enabled: true) }
  let(:workout) { create(:workout, user:) }
  let(:comparison) { described_class.new(workouts: [ workout ], env: { "MODEL" => "candidate" }) }

  it "compares verified summaries without saving them or revealing the variant before diagnosis" do
    content = { sentences: [ { text: "Une sortie tranquille.", fact_ids: [ "baseline:sport" ] },
                             { text: "999999 km.", fact_ids: [ "baseline:distance" ] } ] }.to_json
    endpoint = stub_request(:post, "#{AssistantHelpers::BASE_URL}/v1/chat/completions").to_return(
      status: 200, body: { model: "returned-model", choices: [ { message: { content: } } ] }.to_json
    )
    dir = comparison.call
    expect(endpoint).to have_been_requested.twice
    pairs = File.read(File.join(dir, "pairs.txt"))
    expect(pairs).to include("A: Une sortie tranquille.", "B: Une sortie tranquille.")
    expect(pairs).not_to match(/999999|candidate|returned-model/)
    expect(File.read(File.join(dir, "diagnostics.txt"))).to include("candidate", "999999", "baseline:sport")
    expect(workout.reload.assistant_summary).to be_nil
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "refuses an opted-out account before contacting either model" do
    user.update!(ai_enabled: false)
    expect { comparison.call }.to raise_error(ArgumentError, /not_consented/)
  end
end
