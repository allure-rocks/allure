# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::RequestBodyLimit do
  let(:app) { instance_double(Proc, call: [ 200, {}, [ "ok" ] ]) }
  let(:middleware) { described_class.new(app) }
  let(:overhead) { described_class::OVERHEAD_BYTES }

  def request(method, path, length: nil, body: nil)
    env = Rack::MockRequest.env_for(path, method:, input: body)
    env["CONTENT_LENGTH"] = length&.to_s
    env.delete("CONTENT_LENGTH") if length.nil? && body.nil?
    middleware.call(env)
  end

  it "holds every endpoint to its own limit, before the application runs" do
    {
      [ "POST", "/workout_imports/strava_archive" ] => Allure::StravaArchive::MAX_BYTES + overhead,
      [ "POST", "/api/rest/v1/imports" ] => Allure::StravaArchive::MAX_BYTES + overhead,
      [ "POST", "/workout_imports" ] => Workouts::ArchiveReader::MAX_SOURCE_BYTES + overhead,
      [ "POST", "/session" ] => described_class::DEFAULT_BYTES,
      [ "PATCH", "/workout_imports" ] => described_class::DEFAULT_BYTES
    }.each do |(method, path), limit|
      expect(request(method, path, length: limit).first).to eq(200)
      expect(request(method, path, length: limit + 1).first).to eq(413)
    end
    expect(app).to have_received(:call).exactly(5).times
  end

  it "measures a body sent without a length by what was buffered" do
    stub_const("#{described_class}::DEFAULT_BYTES", 10)
    env = Rack::MockRequest.env_for("/session", method: "POST", input: "x" * 11)
    env.delete("CONTENT_LENGTH")

    expect(middleware.call(env).first).to eq(413)
    expect(app).not_to have_received(:call)
  end

  it "lets requests without a body through" do
    env = Rack::MockRequest.env_for("/feed")
    env.delete("CONTENT_LENGTH")

    expect(middleware.call(env).first).to eq(200)
  end

  it "sits before every middleware that reads a body" do
    classes = Rails.application.middleware.map(&:klass)

    expect(classes.index(described_class)).to be < classes.index(Rack::MethodOverride)
    expect(classes.index(described_class)).to be < classes.index(OmniAuth::Builder)
  end
end
