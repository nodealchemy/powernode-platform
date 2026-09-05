# frozen_string_literal: true

require "rails_helper"

# APO increment `app-5` — the "Project Operations" template as seeded data.
#
# Two properties matter here and neither is about membership repair:
#
#   1. the template names three CORE canonicals (observer / deployer / SRE) and
#      the SRE leads it;
#   2. it materialises NOTHING for the account. It is marked `per_project`, so
#      Ai::Teams::CanonicalTeamReconciler's account-level walk must skip it —
#      otherwise every reconcilable account silently acquires a team and three
#      agent clones on every boot, and `drift` reports the account team it
#      deliberately does not have as drift that no reconcile can clear.
#
# The second is asserted on ROWS (no team, no extra clones) and on the walk
# itself, because a marker nothing reads is not a control.
RSpec.describe "ai_project_operations_team_seed" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account)   { create(:account, name: "Powernode Admin") }
  let!(:user)      { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

  # The three canonicals the template names, minted directly rather than by
  # running six agent seeds: this spec is about the TEMPLATE, and the seed
  # resolves its seats by slug at materialisation time, not at seed time.
  def canonical(slug, name)
    create(:ai_agent, :global, owner_account: account, slug: slug, source_key: slug,
                               name: name, agent_type: "monitor", is_system: true)
  end

  let!(:sre)      { canonical("infrastructure-health-monitor", "Infrastructure Health Monitor") }
  let!(:deployer) { canonical("release-manager", "Release Manager") }
  let!(:observer) { canonical("system-health-monitor", "System Health Monitor") }

  let(:slug) { Ai::Projects::TeamProvisioner::TEMPLATE_SLUG }
  let(:template) { Ai::TeamTemplate.global.find_by(slug: slug) }

  before { load_seed!("ai_project_operations_team_seed.rb") }

  it "seeds a global, is_system, source_key-managed canonical template" do
    expect(template).to be_present
    expect(template).to be_global
    expect(template.is_system).to be true
    expect(template.source_key).to eq(slug)
    expect(template).to be_canonical
    expect(template.name).to eq("Project Operations")
  end

  it "names the observer, the deployer and the SRE, with the SRE leading" do
    expect(template.member_definitions.map { |d| d["agent_slug"] })
      .to eq(%w[infrastructure-health-monitor release-manager system-health-monitor])
    expect(template.member_definitions.map { |d| d["member_role"] })
      .to eq(%w[manager executor analyst])
    expect(template.manager_definition["agent_slug"]).to eq("infrastructure-health-monitor")
  end

  it "is marked per_project, so nothing materialises it for the account" do
    expect(template.default_config[Ai::Teams::CanonicalTeamSeeder::MATERIALISATION_KEY])
      .to eq(Ai::Teams::CanonicalTeamSeeder::MATERIALISATION_PROJECT)
    expect(Ai::Teams::CanonicalTeamReconciler.per_project?(template)).to be true
  end

  it "materialises NO account team when it is seeded" do
    expect(account.ai_agent_teams.where(template_id: template.id)).to be_empty
  end

  it "is SKIPPED by the account-level reconcile walk — no team, no minted clones" do
    before_agents = Ai::Agent.where(account_id: account.id).count

    Ai::Teams::CanonicalTeamReconciler.reconcile_all!(account: account)

    expect(account.ai_agent_teams.where(template_id: template.id)).to be_empty
    expect(Ai::Agent.where(account_id: account.id).count).to eq(before_agents)
    expect(Ai::Teams::CanonicalTeamReconciler.account_materialised_templates.map(&:slug))
      .not_to include(slug)
  end

  it "is SKIPPED by the account-level drift walk, so it never reports a permanent false drift" do
    reports = Ai::Teams::CanonicalTeamReconciler.drift_all(account: account)

    expect(reports.map(&:template_slug)).not_to include(slug)
  end

  it "is idempotent — a second load changes nothing" do
    expect { load_seed!("ai_project_operations_team_seed.rb") }
      .to change { Ai::TeamTemplate.count }.by(0)

    expect(template.member_definitions.size).to eq(3)
  end
end
