# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Parsers::RemoteComment do
  let(:thread_uri) { "https://allure.test/api/v1/trail/abc" }

  def activity(**overrides)
    federation_comment_activity(in_reply_to: thread_uri, to: "https://allure.test/users/marie").tap do |document|
      document["object"].merge!(overrides.transform_keys(&:to_s))
    end
  end

  def parse(document) = described_class.new(document).call

  it "parses the strict comment profile" do
    value = parse(activity)

    expect(value.object_uri).to eq("https://remote.example/api/v1/comment/c1")
    expect(value.attributed_to).to eq("https://remote.example/users/demo")
    expect(value.in_reply_to).to eq(thread_uri)
    expect(value.content_html).to eq("Belle sortie !<br>On y retourne ?")
    expect(value.body).to eq("Belle sortie ! On y retourne ?")
    expect(value.published_at).to eq(Time.utc(2026, 10, 5, 9, 12, 44))
    expect(value.warnings).to be_empty
  end

  it "sanitizes the content and keeps unknown keys in raw" do
    value = parse(activity(content: "<p>Bravo <script>alert(1)</script><a href=\"javascript:x\">lien</a></p>",
                           tag: [ { "type" => "Mention", "href" => "https://allure.test/users/marie" } ]))

    expect(value.content_html).not_to include("<script", "javascript:")
    expect(value.body).to start_with("Bravo").and end_with("lien")
    expect(value.raw["tag"]).to be_present
  end

  it "refuses every whole-document violation" do
    other = "https://elsewhere.example/users/eve"
    {
      "not a Note" => activity(type: "Article"),
      "foreign attribution" => activity(attributedTo: other),
      "id on another authority" => activity(id: "https://elsewhere.example/api/v1/comment/c1"),
      "id with a fragment" => activity(id: "https://remote.example/api/v1/comment/c1#x"),
      "no inReplyTo" => activity(inReplyTo: nil),
      "relative inReplyTo" => activity(inReplyTo: "/api/v1/trail/abc"),
      "no content" => activity(content: nil),
      "blank content" => activity(content: "<p> </p>"),
      "oversized content" => activity(content: "a" * (described_class::MAX_CONTENT_BYTES + 1)),
      "text over the comment bound" => activity(content: "a" * (Comment::MAX_BODY_LENGTH + 1))
    }.each do |case_name, document|
      expect { parse(document) }.to raise_error(described_class::InvalidObject), case_name
    end

    expect { parse(activity.merge("object" => "https://remote.example/api/v1/comment/c1")) }
      .to raise_error(described_class::InvalidObject)
  end

  it "refuses an object larger than the retained bound" do
    document = activity(summary: "x" * described_class::MAX_RAW_BYTES)

    expect { parse(document) }.to raise_error(described_class::InvalidObject, /too large/)
  end

  it "keeps a malformed publication time as a warning" do
    value = parse(activity(published: "2026-10-05 09:12:44"))

    expect(value.published_at).to be_nil
    expect(value.warnings).to eq([ "invalid published" ])
  end
end
