# frozen_string_literal: true

require "rails_helper"

# IMP-6cda93db7f31 (offer 01a06997) — the core canonical agent seeds on a
# database that holds NO user, NO account and NO provider.
#
# A global canonical (account_id NULL, source_key-managed, is_system) is a
# platform-provided template — proposal §5 ruling 5 — and needs no account to
# exist. Until this task every core agent seed bailed out when the "Powernode
# Admin" account or its admin user was missing, so a development database
# seeded without SEED_ADMIN_USERS held no canonical at all, and on 2026-09-03
# `rake claude:sync_agents` read that empty set as "every committed skeleton
# is stale" and deleted 15 files under .claude/agents/powernode/. The exporter
# now refuses to clean up on an empty set (core cde3bf9f1); this spec pins the
# other half of the operator direction: the canonical rows themselves seed
# unconditionally, and ONLY the account-scoped follow-on rows (trust scores,
# approval chains, policy rows, budgets, lineage, the demo agents) wait for an
# account.
#
# The slug lists are pinned per seed FILE so a regression names the file. The
# union is the whole core forest ai_agent_hierarchy_seed.rb attaches (its two
# roots plus CORE_HIERARCHY_CHILD_SLUGS + ENGINEERING_HIERARCHY_CHILD_SLUGS) —
# keep the three in step.
module CoreCanonicalSeedsWithoutUsers
  CANONICAL_SLUGS_BY_SEED = {
    "claude_agents_seed.rb" => %w[strategic-planner research-analyst],
    "monitoring_analytics_agents_seed.rb" => %w[
      system-performance-monitor system-analytics-intelligence
      system-health-monitor system-quality-assurance
    ],
    "ai_utility_agents_seed.rb" => %w[
      prd-generator llm-judge knowledge-graph-curator rag-reranker rag-query-engine intent-classifier
    ],
    "ai_concierge_seed.rb" => %w[powernode-assistant],
    "autonomy_data_seed.rb" => %w[infrastructure-health-monitor process-automation-optimizer visual-design-assistant],
    "ai_engineering_agents_seed.rb" => %w[platform-architect platform-developer release-manager documentation-specialist]
  }.freeze

  SEED_FILES = CANONICAL_SLUGS_BY_SEED.keys.freeze
  ALL_SLUGS  = CANONICAL_SLUGS_BY_SEED.values.flatten.freeze
end

RSpec.describe "core canonical agent seeds on a database with no users" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  def seed_all!
    CoreCanonicalSeedsWithoutUsers::SEED_FILES.each { |f| load_seed!(f) }
  end

  # ai_concierge_seed binds the concierge's routing skill and raises without
  # it. The skill is GLOBAL baseline content (ai_skills_seed.rb runs first in
  # db/seeds.rb); the row is all the seed needs here.
  let!(:concierge_skill) do
    create(:ai_skill, :global, slug: "powernode-concierge", name: "Powernode Concierge", is_system: true)
  end

  before do
    # The premise: nothing an account-scoped row could hang on exists.
    expect(User.count).to eq(0)
    expect(Account.count).to eq(0)
    expect(Ai::Provider.count).to eq(0)
  end

  CoreCanonicalSeedsWithoutUsers::CANONICAL_SLUGS_BY_SEED.each do |file, slugs|
    it "#{file} seeds #{slugs.join(', ')} as global canonicals" do
      load_seed!(file)

      missing = slugs.reject { |slug| Ai::Agent.global.exists?(slug: slug) }
      expect(missing).to be_empty, "#{file} did not seed: #{missing.join(', ')}"
    end
  end

  it "seeds the whole core canonical set — global, is_system, source_key-managed — and nothing account-scoped" do
    seed_all!

    expect(Ai::Agent.global.pluck(:slug).sort).to eq(CoreCanonicalSeedsWithoutUsers::ALL_SLUGS.sort)
    Ai::Agent.global.find_each do |agent|
      expect(agent.account_id).to be_nil
      expect(agent.is_system).to be(true), "#{agent.slug} should be is_system"
      expect(agent.source_key).to eq(agent.slug)
      expect(agent.status).to eq("active")
    end
    expect(Ai::Agent.account_scoped.count).to eq(0)
  end

  it "keeps every account-scoped follow-on row gated on an account" do
    seed_all!

    expect(Ai::AgentTrustScore.count).to eq(0)
    expect(Ai::AgentBudget.count).to eq(0)
    expect(Ai::ApprovalChain.count).to eq(0)
    expect(Ai::InterventionPolicy.count).to eq(0)
    expect(Ai::AgentLineage.count).to eq(0)
  end

  it "is stable when the admin account appears later: a re-seed adds no canonical and keeps every id" do
    seed_all!
    ids_before = Ai::Agent.global.pluck(:slug, :id).to_h

    account = create(:account, name: "Powernode Admin")
    create(:user, account: account, email: "admin@powernode.org")
    %w[anthropic openai ollama custom].each do |type|
      create(:ai_provider, account: account, provider_type: type, is_active: true)
    end

    seed_all!

    expect(Ai::Agent.global.pluck(:slug, :id).to_h).to eq(ids_before)
    expect(Ai::Agent.global.count).to eq(CoreCanonicalSeedsWithoutUsers::ALL_SLUGS.size)
  end

  # `find_or_create_global`'s block is CREATE-ONLY, so a canonical first
  # written before the admin account and the providers existed would keep
  # creator_id / ai_provider_id NULL FOREVER — and a provider-less canonical is
  # the row every nil-provider read path (the Claude Code export's model tier,
  # the clone doors, the executor's telemetry) then has to defend against. The
  # columns fill in on the next re-seed instead.
  it "fills in creator and provider on a re-seed once the admin account and its providers exist" do
    seed_all!
    expect(Ai::Agent.global.where(creator_id: nil).count).to eq(Ai::Agent.global.count)

    account = create(:account, name: "Powernode Admin")
    admin = create(:user, account: account, email: "admin@powernode.org")
    %w[anthropic openai ollama custom].each do |type|
      create(:ai_provider, account: account, provider_type: type, is_active: true)
    end

    seed_all!

    ownerless = Ai::Agent.global
                         .where(creator_id: nil).or(Ai::Agent.global.where(ai_provider_id: nil))
                         .pluck(:slug)
    expect(ownerless).to be_empty
    expect(Ai::Agent.global.distinct.pluck(:creator_id)).to eq([ admin.id ])
  end

end
