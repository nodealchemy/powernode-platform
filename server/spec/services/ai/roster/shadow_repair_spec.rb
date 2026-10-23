# frozen_string_literal: true

require "rails_helper"

# ai:roster:repair_shadows — moves the runs and skill-usage rows that landed on a
# GLOBAL canonical (before runtime writers resolved through the shadow) onto the
# account's shadow, with a ledger row per move so the run can be rolled back.
RSpec.describe Ai::Roster::ShadowRepair do
  roster = %w[platform-engineer platform-reviewer powernode-concierge fleet-operator].freeze

  let(:roster) { roster }
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) }
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:out) { StringIO.new }
  let!(:globals) do
    roster.to_h do |slug|
      [ slug, create(:ai_agent, :global, is_system: true, slug: slug, name: slug.titleize, agent_type: "assistant") ]
    end
  end

  before { allow(Ai::Agents::CanonicalRoster).to receive(:slugs).and_return(roster) }

  def execution_on(agent, acct: account)
    create(:ai_agent_execution, account: acct, agent: agent, user: owner, provider: provider)
  end

  def usage_on(agent, acct: account)
    create(:ai_skill_usage_record, account: acct, ai_agent: agent)
  end

  def shadow(slug) = Ai::Agent.owned_by_account(account.id).find_by(slug: slug)

  # Three executions and two usage records on the global engineer, one execution on the global reviewer.
  let!(:rows) do
    [ execution_on(globals["platform-engineer"]), execution_on(globals["platform-engineer"]),
      execution_on(globals["platform-engineer"]), execution_on(globals["platform-reviewer"]),
      usage_on(globals["platform-engineer"]), usage_on(globals["platform-engineer"]) ]
  end

  def repair(**opts) = described_class.new(out: out, **opts)

  describe "dry run (the default)" do
    it "changes nothing, mints nothing, and prints the count, the first 3 and the last 1" do
      expect { repair.dry_run }.not_to change { [ Ai::Agent.count, Ai::RosterMigrationRun.count, rows.map { |r| r.reload.ai_agent_id } ] }

      text = out.string
      expect(text).to include("This will affect 6 rows")
      expect(text.scan(/^\s+first \d/).size).to eq(3)
      expect(text.scan(/^\s+last /).size).to eq(1)
      expect(text).to include("ai_agent_executions", "ai_skill_usage_records", "platform-engineer")
    end
  end

  describe "APPLY" do
    it "mints the four shadows, re-points every row, and writes one ledger row per move" do
      run_id = repair.apply!

      roster.each { |slug| expect(shadow(slug)).to be_present.and have_attributes(cloned_from_id: globals[slug].id) }
      engineer = shadow("platform-engineer").id
      expect(rows.map { |r| r.reload.ai_agent_id }).to eq([ engineer, engineer, engineer, shadow("platform-reviewer").id, engineer, engineer ])
      ledger = Ai::RosterMigrationRun.where(kind: "shadow_repair", run_id: run_id, table_name: %w[ai_agent_executions ai_skill_usage_records])
      expect(ledger.count).to eq(6)
      expect(ledger.find_by(record_id: rows.first.id)).to have_attributes(
        table_name: "ai_agent_executions", from_id: globals["platform-engineer"].id, to_id: engineer, account_id: account.id
      )
      expect(Ai::AgentExecution.where(ai_agent_id: globals.values.map(&:id))).to be_empty
      expect(Ai::SkillUsageRecord.where(ai_agent_id: globals.values.map(&:id))).to be_empty
    end

    it "is idempotent: a second APPLY moves nothing and writes no ledger row" do
      repair.apply!
      expect { expect(repair.apply!).to be_nil }
        .not_to change { [ Ai::Agent.count, Ai::RosterMigrationRun.count ] }
    end

    it "skips an account whose shadow cannot be minted, naming the reason, and moves nothing of it" do
      lonely = create(:account)
      create(:ai_provider, account: lonely, is_active: true)
      execution = create(:ai_agent_execution, account: lonely, agent: globals["platform-engineer"], user: owner, provider: provider)

      repair.apply!

      expect(execution.reload.ai_agent_id).to eq(globals["platform-engineer"].id)
      expect(out.string).to include("skipped", lonely.id, "no_mintable_principal")
    end
  end

  describe "ROLLBACK" do
    it "restores every moved row from the ledger, and a second rollback is a no-op" do
      before_ids = rows.map { |r| r.reload.ai_agent_id }
      run_id = repair.apply!

      repair.rollback!(run_id)

      expect(rows.map { |r| r.reload.ai_agent_id }).to eq(before_ids)
      expect { repair.rollback!(run_id) }.not_to change { rows.map { |r| r.reload.ai_agent_id } }
    end

    it "leaves a row alone that moved on since the repair" do
      run_id = repair.apply!
      other = create(:ai_agent, account: account)
      rows.first.update_columns(ai_agent_id: other.id)

      repair.rollback!(run_id)

      expect(rows.first.reload.ai_agent_id).to eq(other.id)
      expect(rows.second.reload.ai_agent_id).to eq(globals["platform-engineer"].id)
    end

    it "refuses an unknown run id" do
      expect { repair.rollback!(SecureRandom.uuid) }.to raise_error(described_class::UnknownRun)
    end
  end

  describe "the rake task" do
    def run_task(env = {})
      keys = %w[APPLY ROLLBACK]
      previous = keys.to_h { |k| [ k, ENV[k] ] }
      keys.each { |k| ENV.delete(k) }
      env.each { |k, v| ENV[k] = v }
      previous_application = Rake.application
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/ai_roster", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      captured = StringIO.new
      original = $stdout
      $stdout = captured
      Rake::Task["ai:roster:repair_shadows"].invoke
      captured.string
    ensure
      $stdout = original
      Rake.application = previous_application
      previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "is a dry run without APPLY, applies with APPLY=1 and reverses with ROLLBACK=<run_id>" do
      expect(run_task).to include("This will affect")
      expect(Ai::AgentExecution.where(ai_agent_id: globals["platform-engineer"].id).count).to eq(3)

      applied = run_task("APPLY" => "1")
      run_id = applied[/run_id=(\S+)/, 1]
      expect(run_id).to be_present
      expect(Ai::AgentExecution.where(ai_agent_id: globals["platform-engineer"].id)).to be_empty

      run_task("ROLLBACK" => run_id)
      expect(Ai::AgentExecution.where(ai_agent_id: globals["platform-engineer"].id).count).to eq(3)
    end
  end
end
