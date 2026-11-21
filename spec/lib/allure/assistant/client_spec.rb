# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Assistant::Client do
  subject(:client) do
    described_class.new(
      base_url: "http://litellm.test:4000/",
      model: "qwen",
      api_key: api_key,
      request_options: request_options
    )
  end

  let(:url) { "http://litellm.test:4000/v1/chat/completions" }
  let(:api_key) { "sk-virtual" }
  let(:request_options) { {} }
  let(:bodies) { [] }
  let(:schema) do
    {
      "type" => "object",
      "additionalProperties" => false,
      "required" => [ "title" ],
      "properties" => { "title" => { "type" => "string" } }
    }
  end
  let(:answer) do
    {
      "id" => "chatcmpl-1",
      "model" => "qwen-3.8-27b",
      "choices" => [
        { "finish_reason" => "stop", "message" => { "role" => "assistant", "content" => '{"title":"Le tour du lac"}' } }
      ],
      "usage" => { "prompt_tokens" => 120, "completion_tokens" => 40, "total_tokens" => 160 }
    }
  end

  def json_response(body, status: 200)
    { status:, body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" } }
  end

  def stub_completion(body: answer, status: 200)
    stub_request(:post, url).to_return do |request|
      bodies << JSON.parse(request.body)
      json_response(body, status:)
    end
  end

  def body_sent
    bodies.last
  end

  it "sends the documented request and returns the answer" do
    stub_completion

    result = client.complete(system: "You write summaries.", user: "Facts:\n- distance", schema:)

    expect(result.content).to eq('{"title":"Le tour du lac"}')
    expect(result.model).to eq("qwen-3.8-27b")
    expect(result.prompt_tokens).to eq(120)
    expect(result.completion_tokens).to eq(40)
    expect(result.calls).to eq(1)
    expect(result).not_to be_prompt_only

    expect(body_sent).to include(
      "model" => "qwen",
      "temperature" => 0.3,
      "max_tokens" => described_class::MAX_TOKENS,
      "stream" => false
    )
    expect(body_sent["messages"]).to eq(
      [
        { "role" => "system", "content" => "You write summaries." },
        { "role" => "user", "content" => "Facts:\n- distance" }
      ]
    )
    expect(body_sent.dig("response_format", "type")).to eq("json_schema")
    expect(body_sent.dig("response_format", "json_schema")).to include(
      "name" => "workout_summary", "strict" => true, "schema" => schema
    )
  end

  it "calls the chat path of the proxy root with the bearer key" do
    stub_completion

    client.complete(system: "s", user: "u", schema:)

    expect(
      a_request(:post, url).with(headers: { "Authorization" => "Bearer sk-virtual", "Content-Type" => "application/json" })
    ).to have_been_requested
  end

  it "omits the bearer key when none is configured" do
    keyless = described_class.new(base_url: "http://litellm.test:4000", model: "qwen")
    stub_completion

    keyless.complete(system: "s", user: "u", schema:)

    expect(a_request(:post, url).with { |request| request.headers["Authorization"].nil? }).to have_been_requested
  end

  it "merges AI_REQUEST_OPTIONS without letting it own the message list, the model or the format" do
    options = {
      "reasoning_effort" => "none",
      "model" => "other",
      "messages" => [],
      "stream" => true,
      "response_format" => { "type" => "json_object" },
      "top_p" => 0.9
    }
    client = described_class.new(base_url: "http://litellm.test:4000", model: "qwen", request_options: options)
    stub_completion

    client.complete(system: "s", user: "u", schema:)

    expect(body_sent).to include("model" => "qwen", "stream" => false, "reasoning_effort" => "none", "top_p" => 0.9)
    expect(body_sent["messages"].length).to eq(2)
    expect(body_sent.dig("response_format", "type")).to eq("json_schema")
  end

  it "asks for JSON in the prompt when no schema is given" do
    stub_completion

    result = client.complete(system: "s", user: "u")

    expect(result).to be_prompt_only
    expect(body_sent).not_to have_key("response_format")
  end

  it "drops a reasoning block the model left in its content" do
    with_reasoning = answer.merge(
      "choices" => [
        { "finish_reason" => "stop",
          "message" => {
            "role" => "assistant",
            "content" => "thinkingI should cite the record.</think>\n\n{\"title\":\"Le tour\"}"
          } }
      ]
    )
    stub_completion(body: with_reasoning)

    expect(client.complete(system: "s", user: "u", schema:).content).to eq('{"title":"Le tour"}')
  end

  it "captures the reasoning only when the caller asks for it" do
    body = answer.merge(
      "choices" => [
        { "finish_reason" => "stop",
          "message" => { "role" => "assistant", "content" => '{"title":"Le tour"}',
                         "reasoning_content" => "The snow is the story." } }
      ]
    )
    stub_completion(body:)

    quiet = client.complete(system: "s", user: "u")
    captured = client.complete(system: "s", user: "u", capture_reasoning: true)

    expect(quiet.reasoning).to be_nil
    expect(captured.reasoning).to eq("The snow is the story.")
  end

  it "retries once without response_format when the endpoint refuses the schema" do
    refusal = {
      "error" => {
        "message" => "OpenAIException - {'error': \"'response_format.type' must be 'json_schema' or 'text'\"}",
        "type" => "invalid_request_error"
      }
    }
    stub_request(:post, url).to_return(json_response(refusal, status: 400), json_response(answer))

    result = client.complete(system: "s", user: "u", schema:)

    expect(result.calls).to eq(2)
    expect(result).to be_prompt_only
    expect(a_request(:post, url).with { |request| JSON.parse(request.body).key?("response_format") })
      .to have_been_requested.once
    expect(a_request(:post, url).with { |request| !JSON.parse(request.body).key?("response_format") })
      .to have_been_requested.once
  end

  it "does not retry a rejection that does not name the response format" do
    stub_completion(body: { "error" => { "message" => "Invalid API key" } }, status: 401)

    expect {
      client.complete(system: "s", user: "u", schema:)
    }.to raise_error(described_class::InvalidRequestError, "Invalid API key")

    expect(a_request(:post, url)).to have_been_requested.once
  end

  it "treats 429, 5xx and a transport failure as retryable" do
    stub_completion(body: { "error" => { "message" => "Too many requests" } }, status: 429)
    expect {
      client.complete(system: "s", user: "u", schema:)
    }.to raise_error(described_class::UnavailableError, /Too many requests/)

    stub_completion(body: { "error" => { "message" => "Upstream is down" } }, status: 503)
    expect {
      client.complete(system: "s", user: "u", schema:)
    }.to raise_error(described_class::UnavailableError, /Upstream is down/)

    stub_request(:post, url).to_timeout
    expect {
      client.complete(system: "s", user: "u", schema:)
    }.to raise_error(described_class::UnavailableError)
  end

  it "refuses an answer with no content or no JSON" do
    stub_completion(body: { "choices" => [ { "message" => { "content" => "  " } } ] })
    expect {
      client.complete(system: "s", user: "u", schema:)
    }.to raise_error(described_class::MalformedResponseError, /no content/)

    stub_completion(body: "<html>proxy</html>")
    expect {
      client.complete(system: "s", user: "u", schema:)
    }.to raise_error(described_class::MalformedResponseError, /not JSON/)
  end

  it "falls back to the configured model when the answer names none" do
    stub_completion(body: answer.except("model"))

    expect(client.complete(system: "s", user: "u", schema:).model).to eq("qwen")
  end
end
