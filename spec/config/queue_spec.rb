# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

RSpec.describe "Solid Queue configuration" do
  def queue_config(queues: nil, threads: nil)
    previous_queues = ENV["SOLID_QUEUE_QUEUES"]
    previous_threads = ENV["SOLID_QUEUE_THREADS"]
    ENV["SOLID_QUEUE_QUEUES"] = queues
    ENV["SOLID_QUEUE_THREADS"] = threads
    source = ERB.new(Rails.root.join("config/queue.yml").read).result
    YAML.safe_load(source, aliases: true).fetch("test").fetch("workers").first
  ensure
    ENV["SOLID_QUEUE_QUEUES"] = previous_queues
    ENV["SOLID_QUEUE_THREADS"] = previous_threads
  end

  it "keeps browser-only jobs away from ordinary workers by default" do
    expect(queue_config.fetch("queues")).to eq(%w[default solid_queue_recurring federation federation_media remote_imports webhooks photos])
  end

  it "configures the dedicated route-image worker explicitly" do
    worker = queue_config(queues: "route_images", threads: "1")

    expect(worker).to include("queues" => [ "route_images" ], "threads" => 1)
  end
end
