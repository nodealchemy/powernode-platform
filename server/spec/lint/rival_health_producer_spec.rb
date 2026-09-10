# frozen_string_literal: true

require "spec_helper"
require "find"
require "tmpdir"

# E7 (design section 4.4) — the rollup is the one health score.
#
# `Monitoring::UnifiedService#calculate_health_score` was a second producer:
# a 4x25% blend of provider health, success rate, response time and resource
# checks, computed over AI executions only, rendered on the same screens as
# fleet health derived from something else entirely. Two numbers that answer
# "is this healthy?" and disagree is the defect; deleting one of them is the
# fix, and nothing but a mechanical guard keeps it deleted.
#
# WHY A GREP AND NOT A `respond_to?` CHECK. `respond_to?` proves the method is
# gone from one class. It does not notice the method being reintroduced under
# the same name on a sibling service, which is exactly how the rival came back
# the first time. The tree-wide literal is the assertion that matches the
# failure mode.
#
# ARM STRUCTURE. `FORBIDDEN` is asserted absent across the scanned roots (the
# green arm), and the same scanner is run against a fixture that contains the
# literal (the red arm), so a scanner that silently matches nothing — a bad
# root, a typo'd pattern, a Find that raises and is swallowed — fails here
# rather than passing vacuously forever.
#
# `Monitoring::AlertingService` IS NOT LISTED, AND MUST NOT BE ADDED.
# Design section 4.4 named it alongside the score as a rival producer. That was
# wrong and the lead ruled so during E7: it produces no verdict, it DELIVERS —
# Slack, email, webhook fan-out for events that have no ComponentStatus row.
# A deliverer is not a producer, and there is nothing about it for this guard
# to keep deleted. It is E8's subject, where it becomes the channel seam that
# Platform::Status::Escalation#notify also calls.
#
# E7b ADDS TWO MORE, WITH DIFFERENT SCOPES, AND THE DIFFERENCE IS THE POINT.
#
# `calculate_overall_health_score` is unique in the tree — it existed only on
# Ai::MonitoringHealthService — so it is forbidden tree-wide like the first.
#
# `determine_health_status` is NOT unique. Five definitions existed and E7b
# deletes two: Ai::MonitoringHealthService and AiMonitoringConcern. The other
# three (Devops::BaseExecutor, Ai::Analytics::DashboardService::AiopsMetrics,
# and the business extension's CustomerHealthScore) are correct code on other
# subjects and are explicitly out of E7b's scope (lead ruling). A tree-wide
# literal would therefore go red on three files nobody is going to change, and
# the cheapest way to green it would be to weaken the guard — which is how a
# guard dies. So that literal is scoped to the two files E7b emptied, asserted
# as "these files no longer define it", and the tree-wide claim is not made.
RSpec.describe "rival health-score producers stay deleted (E7, E7b)" do
  # Deliberately NOT the bare word `health_score`: per-provider, per-agent and
  # per-conversation `health_score` keys are unrelated and legitimate, and a
  # guard that fires on those would be turned off within a week.
  FORBIDDEN = [ "calculate_health_score", "calculate_overall_health_score" ].freeze

  # file => the literal it must no longer define. Scoped, per the reasoning in
  # the header. A file that has been deleted outright also satisfies this.
  SCOPED = {
    "app/services/ai/monitoring_health_service.rb" => "def determine_health_status",
    "app/services/concerns/ai_monitoring_concern.rb" => "def determine_health_status"
  }.freeze

  # Core only. The business extension has its OWN
  # `Analytics::CustomerHealthScoreService#calculate_health_score` — customer
  # churn scoring, an entirely different subject that E7 does not touch — so
  # scanning extensions/ here would fail on a correct file.
  ROOTS = %w[app lib].map { |dir| File.expand_path("../../#{dir}", __dir__) }.freeze

  # Returns [hits, files_scanned]. The count is not decoration: without it, a
  # ROOTS entry pointing at a path that does not exist makes the green arm
  # below pass while reading nothing at all, and the fixture arm would not
  # notice because it scans a tmpdir instead.
  def scan(root)
    hits = []
    files = 0
    return [ hits, files ] unless File.directory?(root)

    Find.find(root) do |path|
      next unless File.file?(path)
      next unless File.extname(path) == ".rb"

      files += 1
      File.foreach(path).with_index(1) do |line, number|
        FORBIDDEN.each do |needle|
          hits << "#{needle} at #{path}:#{number}" if line.include?(needle)
        end
      end
    end
    [ hits, files ]
  end

  it "actually reads the core tree, so the green arm below is not vacuous" do
    # Per root: it exists, so a typo'd path fails here rather than silently
    # contributing zero hits. In aggregate: the scan really walked the app
    # tree. Deliberately NOT a per-root floor — server/lib is legitimately a
    # handful of files, and a threshold it cannot meet would be turned off.
    ROOTS.each do |root|
      expect(File.directory?(root)).to be(true), "lint root does not exist: #{root}"
    end

    expect(ROOTS.sum { |root| scan(root).last }).to be > 200
  end

  it "finds no call to or definition of the tree-wide deleted methods in core" do
    hits = ROOTS.flat_map { |root| scan(root).first }

    expect(hits).to be_empty,
      "E7 deleted Monitoring::UnifiedService#calculate_health_score and E7b deleted " \
      "Ai::MonitoringHealthService#calculate_overall_health_score. The status-plane " \
      "rollup (Platform::Status::Rollup over Platform::Status::Query rows) is the one " \
      "health score. Reintroduced at:\n  #{hits.join("\n  ")}"
  end

  # The scoped half. Deliberately per-file rather than tree-wide: see the header.
  SCOPED.each do |relative_path, needle|
    it "no longer defines #{needle.sub('def ', '')} in #{relative_path}" do
      absolute = File.expand_path("../../#{relative_path}", __dir__)
      next unless File.exist?(absolute) # deleting the file outright is also a pass

      expect(File.read(absolute)).not_to include(needle),
        "E7b deleted this definition; the rollup is the one verdict. It is back in " \
        "#{relative_path}."
    end
  end

  # One red arm PER LITERAL, not one for the set: a scanner that matched only
  # the first needle would pass a single combined fixture and leave the second
  # literal unguarded forever.
  FORBIDDEN.each do |needle|
    it "reports a hit when #{needle} IS present, so the green arm means something" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "reintroduced.rb"), <<~FIXTURE)
          module Monitoring
            class RivalService
              def #{needle}
                42
              end
            end
          end
        FIXTURE

        hits = scan(dir).first
        expect(hits.size).to eq(1)
        expect(hits.first).to start_with(needle)
      end
    end
  end

  # The scoped half needs its own red arm, because the per-file examples above
  # assert an ABSENCE and would pass just as happily against a needle that can
  # never match anything.
  it "the scoped needle matches a file that does define it" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "rival.rb")
      File.write(path, "class X\n  def determine_health_status\n    'healthy'\n  end\nend\n")

      SCOPED.each_value do |needle|
        expect(File.read(path)).to include(needle)
      end
    end
  end
end
