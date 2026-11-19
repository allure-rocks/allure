# frozen_string_literal: true

# The workout assistant in specs (docs/dev/AI.md). `assistant: true` turns the
# feature on against a test endpoint; `stub_assistant` answers one completion
# with the documented OpenAI-compatible shape.
module AssistantHelpers
  BASE_URL = "http://litellm.assistant.test:4000"
  MODEL = "qwen"

  def assistant_answer(content: '{"title":"Le tour du lac"}', model: MODEL, prompt_tokens: 120, completion_tokens: 40)
    {
      "id" => "chatcmpl-spec",
      "model" => model,
      "choices" => [
        { "finish_reason" => "stop", "message" => { "role" => "assistant", "content" => content } }
      ],
      "usage" => { "prompt_tokens" => prompt_tokens, "completion_tokens" => completion_tokens,
                   "total_tokens" => prompt_tokens + completion_tokens }
    }
  end

  def stub_assistant(body: assistant_answer, status: 200)
    stub_request(:post, "#{BASE_URL}/v1/chat/completions").to_return(
      status:,
      body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end
end

RSpec.configure do |config|
  config.include AssistantHelpers

  # The assistant is off in every example whatever the shell configures: the
  # developer's .env must not change what a spec sees. `assistant: true` turns
  # it on against the test endpoint.
  config.around(:each) do |example|
    keys = %w[AI_BASE_URL AI_MODEL AI_API_KEY AI_REQUEST_OPTIONS AI_TIMEOUT AI_MAX_REQUESTS_PER_DAY]
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    if example.metadata[:assistant]
      ENV["AI_BASE_URL"] = AssistantHelpers::BASE_URL
      ENV["AI_MODEL"] = AssistantHelpers::MODEL
    end
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
