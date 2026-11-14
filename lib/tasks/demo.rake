# frozen_string_literal: true

# The demo instance's seed task (PLAN_DEMO.md §5). The boot chain runs it on
# every fresh database; an operator may re-run it by hand at any time — it is
# idempotent and never wipes anything.
namespace :demo do
  desc "Seed the demo dataset with every date re-anchored on the present (DEMO_INSTANCE only)"
  task reset: :environment do
    begin
      summary = Demo::Reset.new(out: $stdout).call
    rescue Demo::Reset::NotDemoInstance, Demo::Reset::MissingSeedFiles,
           Allure::Demo::InvalidConfiguration => error
      abort "[demo:reset] #{error.message}"
    end
    warn "[demo:reset] #{summary.imported} workouts imported, #{summary.skipped} already present, #{summary.failed} failures"
    abort "[demo:reset] #{summary.failed} step(s) failed; see the lines above" if summary.failed.positive?
  end

  desc "Rewrite db/seeds/demo/corpus_files.txt, the corpus files the demo image carries"
  task corpus_files: :environment do
    require Rails.root.join("db/seeds/demo/corpus_files")
    DemoSeed::CorpusFiles.write!
    puts "[demo:corpus_files] #{DemoSeed::CorpusFiles.from_manifests.length} files listed"
  end
end
