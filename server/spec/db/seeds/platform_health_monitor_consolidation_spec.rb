# frozen_string_literal: true

require "rails_helper"

# IMP-80a353489ba4 — four core monitoring canonicals (System Performance
# Monitor, System Analytics Intelligence, System Health Monitor, Infrastructure
# Health Monitor) were four prompts for one job: none owned a sensor, a policy
# set, a schedule or a health verb, and each named another as its alternative.
# Operator direction: one Platform Health Monitor; System Quality Assurance
# stays under Engineering.
#
# Seeds never re-run on a deployed plane after first boot, but they do on every
# dev install, CI database and fresh plane, so the seed also retires what an
# earlier seed wrote there:
#   * the Infrastructure Health Monitor row is ADOPTED in place — same id, so
#     its skills, trust score, budgets, executions and account clones follow;
#   * the other three are ARCHIVED, never destroyed: Ai::Agent destroys its
#     executions, conversations and messages, and an archived row leaves the
#     canonical roster (RoutableAgents reads active agents only).
RSpec.describe "Platform Health Monitor consolidation (monitoring seeds)" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let(:retired_monitor_slugs) { %w[system-performance-monitor system-analytics-intelligence system-health-monitor] }

  let!(:account)   { create(:account, name: "Powernode Admin") }
  let!(:user)      { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

  let(:monitor) { Ai::Agent.global.find_by(slug: "platform-health-monitor") }

  def seed_monitoring!
    load_seed!("monitoring_analytics_agents_seed.rb")
    load_seed!("autonomy_data_seed.rb")
  end

  def legacy_canonical(slug, name, agent_type: "monitor")
    create(:ai_agent, :global, owner_account: account, slug: slug, source_key: slug, name: name,
                               agent_type: agent_type, is_system: true, status: "active")
  end

  it "seeds ONE Platform Health Monitor in place of the four overlapping monitors, and keeps QA" do
    seed_monitoring!

    expect(monitor).to be_present
    expect(monitor).to have_attributes(name: "Platform Health Monitor", agent_type: "monitor",
                                       source_key: "platform-health-monitor", is_system: true, status: "active")
    (retired_monitor_slugs + %w[infrastructure-health-monitor]).each do |slug|
      expect(Ai::Agent.exists?(slug: slug)).to be(false), "#{slug} is still seeded"
    end
    expect(Ai::Agent.global.find_by(slug: "system-quality-assurance")).to have_attributes(status: "active")
  end

  it "grounds its prompt in the health verbs that exist, not generic monitoring prose" do
    seed_monitoring!

    prompt = monitor.mcp_metadata["system_prompt"]
    expect(prompt).to include("get_system_health", "health_check", "failover_check")
    expect(prompt).not_to match(/powernode-(backend|worker|frontend)@/)
  end

  it "adopts an existing Infrastructure Health Monitor row in place, keeping its id and what hangs off it" do
    legacy = legacy_canonical("infrastructure-health-monitor", "Infrastructure Health Monitor")
    trust = Ai::AgentTrustScore.create!(agent_id: legacy.id, account: account, tier: "trusted")

    seed_monitoring!

    expect(monitor.id).to eq(legacy.id)
    expect(monitor).to have_attributes(name: "Platform Health Monitor", source_key: "platform-health-monitor",
                                       status: "active")
    expect(Ai::Agent.global.where(slug: "platform-health-monitor").count).to eq(1)
    expect(Ai::AgentTrustScore.find(trust.id).agent_id).to eq(legacy.id)
  end

  it "archives, never destroys, the other three monitors an earlier seed wrote" do
    legacy = {
      "system-performance-monitor" => legacy_canonical("system-performance-monitor", "System Performance Monitor"),
      "system-analytics-intelligence" => legacy_canonical("system-analytics-intelligence", "System Analytics Intelligence",
                                                          agent_type: "data_analyst"),
      "system-health-monitor" => legacy_canonical("system-health-monitor", "System Health Monitor")
    }

    seed_monitoring!

    legacy.each do |slug, row|
      expect(Ai::Agent.find_by(id: row.id)).to have_attributes(status: "archived"), "#{slug} was not archived"
    end
    expect(Ai::Routing::RoutableAgents.canonical.map(&:slug)).not_to include(*retired_monitor_slugs)
    expect(Ai::Routing::RoutableAgents.canonical.map(&:slug)).to include("platform-health-monitor")
  end

  # A demo install seeds ai_example_templates_seed's account-scoped showcase copy
  # (same generated slug) before this seed runs, and find_or_initialize_global
  # converts that row to the global one in place. A create-only block would
  # leave the canonical carrying the showcase copy's prompt instead of this one.
  it "applies its definition to a row converted from an account-scoped copy" do
    create(:ai_agent, account: account, slug: "platform-health-monitor", name: "Platform Health Monitor",
                      agent_type: "monitor", description: "Showcase copy.",
                      mcp_metadata: { "system_prompt" => "Infrastructure health monitor for distributed systems." })

    seed_monitoring!

    expect(monitor.account_id).to be_nil
    expect(monitor.description).to start_with("Measures and reports the health of the Powernode platform")
    expect(monitor.mcp_metadata["system_prompt"]).to include("get_system_health")
  end

  # The seed's own rescue: `retired.update!(status: "archived")` goes through
  # ActiveRecord validations, and a retired row a LATER change made invalid
  # (blank name, here — column-written to bypass validation getting it there,
  # exactly as a bad migration or a hand edit could leave a row) must not
  # abort the seed run for every other row. Before this example nothing
  # exercised the `rescue ActiveRecord::RecordInvalid` branch — a row could
  # only ever take the happy `update!` path in CI, so the fallback
  # `update_columns` call had never actually run.
  it "still archives a retired row by column write when update! raises RecordInvalid" do
    legacy = legacy_canonical("system-health-monitor", "System Health Monitor")
    legacy.update_column(:name, "") # invalid (name presence), bypassing validation to get there

    expect { seed_monitoring! }.not_to raise_error

    expect(legacy.reload).to have_attributes(status: "archived", name: "")
  end

  it "archives a stray Infrastructure Health Monitor when the Platform Health Monitor already exists" do
    seed_monitoring!
    stray = legacy_canonical("infrastructure-health-monitor", "Infrastructure Health Monitor")

    seed_monitoring!

    expect(stray.reload.status).to eq("archived")
    expect(Ai::Agent.global.where(slug: "platform-health-monitor").count).to eq(1)
  end

  it "is idempotent — a second load changes no agent row" do
    legacy_canonical("infrastructure-health-monitor", "Infrastructure Health Monitor")
    legacy_canonical("system-health-monitor", "System Health Monitor")
    seed_monitoring!

    snapshot = -> { Ai::Agent.order(:id).pluck(:id, :slug, :name, :status, :source_key) }
    expect { seed_monitoring! }.not_to change(&snapshot)
  end
end
