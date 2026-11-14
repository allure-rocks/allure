# frozen_string_literal: true

require "rails_helper"
require "rake"

# A command printed on the operator site must exist (docs/site/README.md).
RSpec.describe "Operator documentation: rake tasks" do
  let(:pages) { Dir[Rails.root.join("docs/site/**/*.md")].reject { it.include?("/node_modules/") } }

  # `bin/rails db:prepare db:seed` names two tasks; only namespaced names count,
  # so `bin/rails server` or prose after a command is never read as a task.
  let(:named_tasks) do
    commands = pages.flat_map { File.read(it).scan(%r{bin/rails((?: [a-z_]+(?::[a-z_]+)+)+)}).flatten }.flat_map(&:split)
    (commands + reference_tasks).uniq
  end

  # The CLI reference lists tasks in its tables without the `bin/rails` prefix.
  let(:reference_tasks) do
    Rails.root.join("docs/site/reference/cli.md").read.scan(/^\| `([a-z_]+(?::[a-z_]+)+)` \|/).flatten
  end

  it "reads the CLI reference's tables" do
    expect(reference_tasks).to include("users:create", "db:seed")
  end

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  it "names only tasks that exist" do
    expect(named_tasks).not_to be_empty
    expect(named_tasks.reject { Rake::Task.task_defined?(it) }).to be_empty
  end
end
