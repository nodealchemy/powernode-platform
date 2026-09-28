# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"
require "fugit"

# extensions/system/worker/config/sidekiq_system.yml — merged into the main
# worker's sidekiq-scheduler config at boot (worker/config/application.rb).
#
# IMP-9ce0ed39c557 review finding: adding the out_of_band_exec_reaper entry
# first landed with the new block spliced in BETWEEN system_task_reaper's
# `queue:` and `description:` lines — a valid-looking diff that produced a
# schedule where system_task_reaper lost its description and
# out_of_band_exec_reaper carried two (a duplicate YAML mapping key, which
# Psych resolves to the LAST value silently rather than raising). This
# parses the real file and asserts each entry's full, exact shape rather
# than merely "the file loads" — a load-only check would have passed on
# the broken version too.
RSpec.describe "extensions/system worker sidekiq_system.yml scheduler config" do
  let(:path) do
    File.expand_path("../../../extensions/system/worker/config/sidekiq_system.yml", __dir__)
  end

  let(:config) do
    raw = File.read(path)
    YAML.safe_load(ERB.new(raw).result, permitted_classes: [ Symbol ], aliases: true)
  end

  let(:schedule) { config[:schedule] }

  it "declares both system_task_reaper and out_of_band_exec_reaper" do
    expect(schedule).to have_key("system_task_reaper")
    expect(schedule).to have_key("out_of_band_exec_reaper")
  end

  describe "system_task_reaper" do
    subject(:entry) { schedule["system_task_reaper"] }

    it "is untouched by the out_of_band_exec_reaper addition" do
      expect(entry).to eq(
        "cron" => "0 */1 * * *",
        "class" => "SystemTaskReaperJob",
        "queue" => "system",
        "description" => "System: fail abandoned running tasks and cancel unrunnable ones"
      )
    end

    it "has a parseable cron expression" do
      expect(Fugit.parse_cron(entry["cron"])).not_to be_nil
    end
  end

  describe "out_of_band_exec_reaper" do
    subject(:entry) { schedule["out_of_band_exec_reaper"] }

    it "has exactly its own class, cron and description — no leftover from a sibling entry" do
      expect(entry).to eq(
        "cron" => "*/5 * * * *",
        "class" => "OutOfBandExecReaperJob",
        "queue" => "system",
        "description" => "System: fail out-of-band-exec operations stuck executing past timeout"
      )
    end

    it "has a parseable cron expression" do
      expect(Fugit.parse_cron(entry["cron"])).not_to be_nil
    end

    it "fires every 5 minutes — matching timeout_seconds+margin needing a short interval, not the hourly task reaper's window" do
      cron = Fugit.parse_cron(entry["cron"])
      from = Time.utc(2026, 1, 1, 0, 0, 0)
      expect(cron.next_time(from).to_t - from).to eq(300)
    end
  end

  # Review finding C2-3 — deleted the non-failing "raises no YAML::SyntaxError"
  # example this comment used to sit under: Psych never raises on a
  # duplicate key at all (valid YAML — "last value wins"), so that assertion
  # could not fail regardless of whether the file was broken. The two
  # "has exactly its own..." examples above are the real regression guards —
  # they pin each entry's FULL shape, not merely that the file loads.
end
