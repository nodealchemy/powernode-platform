# frozen_string_literal: true

require "rails_helper"

# PRE-3 eval gate: every seeded capability skill's evals, and a fixed 12-task set,
# run THROUGH assemble_task (the domain ceiling, the top five, the read-only filter
# and the requires closure included), on core's and every loaded extension's
# batches and the recorded real embeddings at the production cut-off.
#
# Acceptance (skills-first agents design, PRE-3):
#   * at least 11 of the 12 tasks select what they should;
#   * zero false positives on any `expect_selected: false` eval, across ALL skills.
#
# THE 12: the six v1 eval tasks, plus a review of a finished increment, dev-loop
# finding routing, an onboarding brief, release promotion, a health probe and a
# lane signal. The sixth v1 task is MARKETING, which has no skill until P4 (the
# marketing extension): it is `pending` and COUNTS AS A MISS in the 12 (the
# denominator stays 12), so the gate currently demands the other eleven all pass.
# Extension tasks run only when that extension is loaded (core mode: the
# denominator and the allowance shrink accordingly).
RSpec.describe "assemble_task eval gate", type: :service do
  MIN_PASS = 11

  let!(:account) { create(:account) }
  let(:core_seed) { Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb") }
  let(:entries) do
    dirs = [ Rails.root.join("db", "seeds", "capability_skills") ] +
           Powernode::ExtensionRegistry.all.values.map { |ext| ext[:engine].root.join("db", "seeds", "capability_skills") }
    dirs.select(&:directory?).flat_map { |dir| Ai::Skills::CapabilitySeeder.load_entries(dir) }
  end

  before do
    use_recorded_skill_embeddings!
    seed_with_baseline!(core_seed, *extension_capability_seed_paths)
  end

  def assemble(task, agent_slug)
    Ai::Assembly::Service.new(account: account).call(task: task, agent_slug: agent_slug, context: "claude_code")
  end

  def selected(task, agent_slug) = assemble(task, agent_slug)[:skills].map { |s| s[:slug] }

  # The most specific roster agent for a domain: the one whose ceiling covers it with the
  # fewest domains (a review skill goes to the reviewer, a fleet skill to the operator).
  def agent_for(domain)
    Ai::Agents::CanonicalRoster.each.select { |_slug, spec, _owner| spec[:domains].include?(domain) }
                               .min_by { |_slug, spec, _owner| spec[:domains].size }&.first
  end

  # [task, agent, any-of expected slugs, label, pending reason]
  TWELVE = [
    [ "Work a dev-improve task that adds a migration and a spec", "platform-engineer", %w[dev-loop-execution rails-backend-conventions test-authoring], "v1 dev-improve", nil ],
    [ "Review this campaign increment against its acceptance criteria", "platform-reviewer", %w[acceptance-criteria-review], "v1 review increment", nil ],
    [ "Provision a VM with attached storage for a new project", "fleet-operator", %w[fleet-provisioning-entry storage-operations fleet-capacity-operations], "v1 provision", nil ],
    [ "Help me onboard: I want to set up Powernode for my team", "powernode-concierge", %w[front-door-triage provisioning-brief-capture], "v1 onboarding", nil ],
    [ "Rotate the WireGuard key for an SD-WAN peer", "fleet-operator", %w[sdwan-operations], "v1 wireguard", nil ],
    [ "Plan a marketing campaign for our product launch", "powernode-concierge", %w[marketing], "v1 marketing", "P4: the marketing extension seeds the marketing skills" ],
    [ "Review this finished increment against its acceptance criteria", "platform-reviewer", %w[design-review acceptance-criteria-review], "review of a finished increment", nil ],
    [ "Route a dev-loop finding: improvement, issue or escalate", "platform-engineer", %w[dev-loop-execution], "dev-loop finding routing", nil ],
    [ "Capture an onboarding brief for a new install", "powernode-concierge", %w[provisioning-brief-capture front-door-triage], "onboarding brief", nil ],
    [ "Promote a release from develop to master", "platform-engineer", %w[release-promotion], "release promotion", nil ],
    [ "Probe platform health and report what is down or degraded", "fleet-operator", %w[platform-health-probe], "health probe", nil ],
    [ "Handle a repeated fleet lane signal", "fleet-operator", %w[fleet-signal-handling], "lane signal", nil ]
  ].freeze

  describe "the 12-task set" do
    it "selects the expected skill for at least 11 of 12 (marketing, pending until P4, is the one allowed miss)" do
      runnable = TWELVE.select { |_t, agent, *_| Ai::Agents::CanonicalRoster.include?(agent) }
      results = runnable.map do |task, agent, expected, label, pending|
        got = selected(task, agent)
        { label: label, hit: pending.nil? && (got & expected).any?, pending: pending, got: got, expected: expected }
      end
      score = results.count { |r| r[:hit] }
      RSpec.configuration.reporter.message("  assemble_task 12-task gate: #{score}/#{runnable.size} (pending counts as a miss: #{results.count { |r| r[:pending] }})")

      misses = results.reject { |r| r[:hit] || r[:pending] }
      expect(misses).to be_empty, "gate misses: #{misses.map { |r| "#{r[:label]} wanted #{r[:expected]} got #{r[:got]}" }.join('; ')}"
      expect(score).to be >= (runnable.size == TWELVE.size ? MIN_PASS : runnable.size - 1)
    end

    TWELVE.select { |*_, pending| pending }.each do |task, agent, expected, label, pending|
      it "#{label}: pending #{pending}" do
        pending pending
        expect(selected(task, agent) & expected).not_to be_empty
      end

      it "#{label}: currently comes back uncovered, not guessed" do
        expect(assemble(task, agent)).to include(skills: [])
        expect(assemble(task, agent)[:uncovered]).not_to be_empty
      end
    end
  end

  describe "every seeded skill's evals, through assemble_task" do
    let(:cases) do
      entries.flat_map do |entry|
        Array(entry["evals"]).map do |ev|
          { slug: entry["slug"], task: ev["task"], expected: ev["expect_selected"], domain: entry["domain"] }
        end
      end
    end

    it "has no false positive: a skill is never selected for a task its own eval says it is not for" do
      false_positives = cases.reject { |c| c[:expected] }.filter_map do |c|
        agent = agent_for(c[:domain])
        next unless agent && selected(c[:task], agent).include?(c[:slug])

        "#{c[:slug]} selected for #{c[:task].inspect} (via #{agent})"
      end

      expect(false_positives).to be_empty, "false positives:\n#{false_positives.join("\n")}"
    end

    it "reports the positive hit rate (the gate figure; misses are the discovery ledger's, not new)" do
      positives = cases.select { |c| c[:expected] }
      misses = positives.reject do |c|
        agent = agent_for(c[:domain])
        agent && selected(c[:task], agent).include?(c[:slug])
      end
      RSpec.configuration.reporter.message("  every-eval positives through assemble_task: #{positives.size - misses.size}/#{positives.size}")
      misses.each { |c| RSpec.configuration.reporter.message("    miss: #{c[:slug]} | #{c[:task]}") }

      expect(positives).not_to be_empty
    end
  end
end
