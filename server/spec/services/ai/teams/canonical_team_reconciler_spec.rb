# frozen_string_literal: true

require "rails_helper"

# HIER-P4 — ONE STRUCTURE, THREE VIEWS. A canonical team is an Ai::TeamTemplate
# (nodes + roles, global, source_key-managed) whose membership is VERIFIED
# against the lineage forest (a manager → member edge per member) and the
# delegation graph (the manager's policy admits every member's agent_type and
# the team carries every type the policy admits), and MATERIALISED per account
# as an Ai::AgentTeam whose members are the account's executing principals
# (ruling 8: a global canonical never executes, so the clone sits in the team).
#
# The reconciler repairs MEMBERSHIP only. Lineage edges and delegation rows
# have their own single writers (the hierarchy seeds through
# Ai::Agents::HierarchyWriter); here they are read, reported and never touched.
RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe Ai::Teams::CanonicalTeamReconciler do
  let!(:account)  { create(:account, name: "Powernode Admin") }
  let!(:user)     { create(:user, account: account, email: "admin@powernode.org") }
  let!(:provider) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

  def canonical(name:, slug:, agent_type:)
    create(:ai_agent, :global, owner_account: account, name: name, slug: slug, source_key: slug,
                                agent_type: agent_type, is_system: true)
  end

  let!(:manager)  { canonical(name: "Ops Lead",       slug: "ops-lead",       agent_type: "assistant") }
  let!(:monitor)  { canonical(name: "Ops Monitor",    slug: "ops-monitor",    agent_type: "monitor") }
  let!(:sensor)   { canonical(name: "Ops Sensor",     slug: "ops-sensor",     agent_type: "monitor") }
  let!(:designer) { canonical(name: "Ops Designer",   slug: "ops-designer",   agent_type: "assistant") }

  let(:writer) { Ai::Agents::HierarchyWriter.new(account: account) }

  def attach_all!
    [ monitor, sensor, designer ].each { |child| writer.attach!(child: child, parent: manager, spawn_reason: "seed") }
    writer.ensure_delegation_policy!(agent: manager, inheritance_policy: "moderate", max_depth: 3,
                                     allowed_delegate_types: %w[assistant monitor], allowed_actions: [])
  end

  let(:members) do
    [
      { slug: "ops-lead",     name: "Ops Lead",     role: "manager",    lead: true },
      { slug: "ops-monitor",  name: "Ops Monitor",  role: "executor" },
      { slug: "ops-sensor",   name: "Ops Sensor",   role: "specialist" },
      { slug: "ops-designer", name: "Ops Designer", role: "specialist" }
    ]
  end

  let!(:template) do
    Ai::Teams::CanonicalTeamSeeder.seed!(
      slug: "ops-crew", name: "Ops Crew", description: "The ops crew", category: "operations",
      members: members
    )
  end

  def reconciler = described_class.new(account: account, template: template)
  def team = account.ai_agent_teams.find_by(template_id: template.id)
  def principal(agent) = Ai::Agents::AccountPrincipalResolver.existing(agent, account: account)

  describe "the template" do
    it "is a global, is_system, source_key-managed canonical the seeder re-seeds idempotently" do
      expect(template).to be_global
      expect(template.is_system).to be true
      expect(template.source_key).to eq("ops-crew")
      expect(template.team_topology).to eq("hierarchical")
      expect(template.default_config).to include("coordination_strategy" => "manager_led",
                                                 "communication_pattern" => "hub_spoke",
                                                 "team_type" => "hierarchical")
      expect(template).to be_canonical
      expect(Ai::TeamTemplate.canonical.pluck(:slug)).to eq([ "ops-crew" ])
      expect(template.member_definitions.map { |d| d["agent_slug"] })
        .to eq(%w[ops-lead ops-monitor ops-sensor ops-designer])
      expect(template.manager_definition["agent_slug"]).to eq("ops-lead")

      expect {
        Ai::Teams::CanonicalTeamSeeder.seed!(slug: "ops-crew", name: "Ops Crew", description: "The ops crew",
                                             category: "operations", members: members)
      }.not_to change(Ai::TeamTemplate, :count)
    end
  end

  describe "#reconcile!" do
    before { attach_all! }

    it "materialises the team for the account on the account's principals, never on the canonicals" do
      result = reconciler.reconcile!

      expect(result.created).to be true
      expect(result).to be_changed
      expect(result.members_added).to eq(4)

      expect(team).to be_present
      expect(team).to be_canonical
      expect(team.team_type).to eq("hierarchical")
      expect(team.team_topology).to eq("hierarchical")
      expect(team.coordination_strategy).to eq("manager_led")
      expect(team.communication_pattern).to eq("hub_spoke")
      expect(team.team_config).to include("canonical" => true, "source_key" => "ops-crew")
      expect(team.template).to eq(template)

      expect(team.members.count).to eq(4)
      expect(team.members.includes(:agent).map { |m| m.agent.account_id }.uniq).to eq([ account.id ])
      expect(team.members.includes(:agent).map { |m| m.agent.global? }.uniq).to eq([ false ])

      lead = team.team_lead
      expect(lead.role).to eq("manager")
      expect(lead.agent.cloned_from_id).to eq(manager.id)
      expect(team.members.find_by(ai_agent_id: principal(monitor).id).role).to eq("executor")
      expect(team.members.find_by(ai_agent_id: principal(sensor).id).role).to eq("specialist")
      expect(team.members.by_priority.map { |m| m.agent.cloned_from_id })
        .to eq([ manager.id, monitor.id, sensor.id, designer.id ])

      roles = team.ai_team_roles.order(:priority_order)
      expect(roles.map(&:role_name)).to eq([ "Ops Lead", "Ops Monitor", "Ops Sensor", "Ops Designer" ])
      expect(roles.map(&:role_type)).to eq(%w[manager worker specialist specialist])
      expect(roles.map(&:ai_agent_id)).to eq(team.members.by_priority.map(&:ai_agent_id))
      expect(roles.first.can_delegate).to be true
    end

    it "is idempotent: a second pass changes nothing and mints nothing" do
      reconciler.reconcile!

      expect {
        expect(reconciler.reconcile!).not_to be_changed
      }.to not_change(Ai::Agent, :count)
        .and not_change(Ai::AgentTeamMember, :count)
        .and not_change(Ai::AgentTeam, :count)
    end

    it "repairs membership: re-adds a removed member, drops a stranger, restores a changed role and the lead" do
      reconciler.reconcile!
      stranger = create(:ai_agent, account: account, name: "Stranger", agent_type: "monitor")

      team.members.find_by(ai_agent_id: principal(sensor).id).destroy!
      team.members.create!(agent: stranger, role: "floater")
      team.members.find_by(ai_agent_id: principal(monitor).id).update!(role: "writer")
      team.team_lead.update!(is_lead: false)

      report = reconciler.drift
      expect(report).to be_drifted
      expect(report.missing_members).to eq([ "ops-sensor" ])
      expect(report.extra_members).to eq([ stranger.slug ])
      expect(report.role_mismatches).to eq([ "ops-monitor(writer≠executor)" ])
      expect(report.lead_mismatch).to be true

      result = reconciler.reconcile!
      expect(result.members_added).to eq(1)
      expect(result.members_removed).to eq(1)
      expect(result.members_updated).to be >= 1

      expect(reconciler.drift).not_to be_drifted
      expect(team.members.count).to eq(4)
      expect(team.team_lead.agent.cloned_from_id).to eq(manager.id)
      expect(team.ai_team_roles.where(ai_agent_id: stranger.id)).to be_empty
    end

    it "never adopts a same-named team that is not the canonical materialisation" do
      other = account.ai_agent_teams.create!(name: "Ops Crew", team_type: "sequential",
                                             coordination_strategy: "priority_based")

      result = reconciler.reconcile!

      expect(result.created).to be false
      expect(result.skipped).to include(match(/ops-crew\(name conflict/))
      expect(other.reload.template_id).to be_nil
      expect(team).to be_nil
    end

    it "reports a canonical the template names but the database lacks as skipped, never raising" do
      designer.destroy!

      result = reconciler.reconcile!

      expect(result.skipped).to eq([ "ops-designer(agent absent)" ])
      expect(team.members.count).to eq(3)
    end
  end

  describe "#drift (read-only)" do
    before { attach_all! }

    it "is empty once the three views agree" do
      reconciler.reconcile!

      report = reconciler.drift
      expect(report).not_to be_drifted
      expect(report.present_edges).to match_array(%w[ops-lead/ops-monitor ops-lead/ops-sensor ops-lead/ops-designer])
    end

    it "mints no principal and writes nothing on an account that has none" do
      other_account = create(:account)
      create(:user, account: other_account)
      create(:ai_provider, account: other_account, provider_type: "anthropic", is_active: true)

      report = nil
      expect { report = described_class.new(account: other_account, template: template).drift }
        .to not_change(Ai::Agent, :count).and not_change(Ai::AgentTeam, :count)

      expect(report.team_absent).to be true
      expect(report.missing_members).to eq(%w[ops-lead ops-monitor ops-sensor ops-designer])
      expect(report).to be_drifted
    end

    it "shows a removed lineage edge as team drift — and reconcile! does not write the edge back" do
      reconciler.reconcile!
      Ai::AgentLineage.find_by!(parent_agent_id: manager.id, child_agent_id: sensor.id).terminate!(reason: "spec")

      report = reconciler.drift
      expect(report).to be_drifted
      expect(report.missing_edges).to eq([ "ops-lead/ops-sensor" ])

      reconciler.reconcile!
      expect(Ai::AgentLineage.for_child(sensor.id).active).to be_empty
      expect(reconciler.drift.missing_edges).to eq([ "ops-lead/ops-sensor" ])
    end

    it "shows a manager delegate type the team lacks as drift" do
      reconciler.reconcile!
      writer.ensure_delegation_policy!(agent: manager, allowed_delegate_types: %w[assistant monitor data_analyst])

      report = reconciler.drift
      expect(report).to be_drifted
      expect(report.unrepresented_delegate_types).to eq([ "data_analyst" ])
    end

    it "shows a member the manager's policy cannot delegate to as drift" do
      reconciler.reconcile!
      writer.ensure_delegation_policy!(agent: manager, allowed_delegate_types: %w[monitor])

      report = reconciler.drift
      expect(report).to be_drifted
      expect(report.undelegatable_members).to eq([ "ops-designer(assistant)" ])
    end

    it "ignores the no-such-type sentinel when checking representation" do
      reconciler.reconcile!
      writer.ensure_delegation_policy!(agent: manager, allowed_delegate_types: %w[assistant monitor none])

      expect(reconciler.drift.unrepresented_delegate_types).to be_empty
    end
  end

  describe ".reconcile_all! / .drift_all" do
    before { attach_all! }

    it "walks every canonical template and skips account-scoped or non-system templates" do
      create(:ai_team_template, account: account, name: "Custom", slug: "custom")
      create(:ai_team_template, :system_template, name: "No key", slug: "no-key", source_key: nil)

      results = described_class.reconcile_all!(account: account)
      expect(results.map { |r| r.template.slug }).to eq([ "ops-crew" ])
      expect(described_class.drift_all(account: account).map(&:template_slug)).to eq([ "ops-crew" ])
    end
  end

  # REVIEW FIX (HIER-P4): the boot rake walked Account.all, and materialising a
  # canonical team MINTS an account principal per seat — so every boot created
  # two teams and up to ten agent rows in every tenant. The repair set is the
  # accounts that already hold a canonical team, plus the primary account the
  # seeds materialise in; a tenant with neither is never written to.
  describe ".reconcilable_accounts" do
    before { attach_all! }

    it "excludes a tenant that holds no canonical team" do
      tenant = create(:account, name: "Tenant Co")
      described_class.reconcile_all!(account: account)

      expect(described_class.reconcilable_accounts).to include(account)
      expect(described_class.reconcilable_accounts).not_to include(tenant)
    end

    it "includes an account that already holds one, so drift there is repaired" do
      other = create(:account, name: "Second Materialisation")
      described_class.new(account: other, template: template).reconcile!

      expect(described_class.reconcilable_accounts).to include(other)
    end

    it "includes the primary account named by the site setting even with no team yet" do
      primary = create(:account, name: "Primary Co")
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(described_class::PRIMARY_ACCOUNT_SETTING).and_return("Primary Co")

      expect(described_class.reconcilable_accounts).to include(primary)
    end
  end

  describe "Ai::AgentTeam.canonical" do
    before { attach_all! }

    it "is the scope the reconciler resolves the materialisation with, and agrees with #canonical?" do
      team = described_class.new(account: account, template: template).reconcile!.team
      expect(Ai::AgentTeam.canonical).to eq([ team ])

      # A hand-edited JSON STRING "true" is not canonical to the predicate, so
      # the scope must not match it either.
      team.update!(team_config: team.team_config.merge("canonical" => "true"))
      expect(team.reload).not_to be_canonical
      expect(Ai::AgentTeam.canonical).to be_empty
    end
  end
end
