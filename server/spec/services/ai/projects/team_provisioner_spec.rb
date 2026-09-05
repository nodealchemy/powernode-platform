# frozen_string_literal: true

require "rails_helper"

# APO increment `app-5` (core half) — the PER-PROJECT team.
#
# A project needs an owning team, and the platform already has the machinery to
# materialise one: a canonical Ai::TeamTemplate (nodes + roles) seated with the
# account's EXECUTING PRINCIPALS by Ai::Teams::CanonicalTeamReconciler. This
# increment reuses that path rather than adding a second team-instantiation
# route; the only extension it needs is a PROJECT SCOPE, because the reconciler
# resolves one canonical team per (account, template) and a second project must
# not be handed the first project's team.
#
# THE CANONICAL RULE (ruling 8) holds here as everywhere: a global canonical is
# a template that never executes, so the seats are the account's CLONES, minted
# through Ai::Agents::AccountPrincipalResolver with a canonical_clone lineage
# edge. Seating canonical rows directly would produce a team that could never
# run.
#
# THE LAUNDERING RULE is the sharp one. Ai::DelegationPolicy reads a BLANK
# allowed_delegate_types as UNRESTRICTED, so "narrowing" a policy by writing an
# empty list silently grants everything — a widening dressed as a restriction.
# The guard and the lineage assertion are deliberately separate examples with
# separate oracles: a single example asserting both would let either one carry
# the other, which is how a redundant guard corrupts a mutation oracle.
RSpec::Matchers.define_negated_matcher :avoid_changing, :change

RSpec.describe Ai::Projects::TeamProvisioner do
  let!(:account)  { create(:account, name: "Powernode Admin") }
  let!(:user)     { create(:user, account: account, email: "admin@powernode.org") }
  let!(:provider) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

  def canonical(name:, slug:, agent_type:)
    create(:ai_agent, :global, owner_account: account, name: name, slug: slug, source_key: slug,
                               agent_type: agent_type, is_system: true)
  end

  let!(:sre)      { canonical(name: "Project SRE",      slug: "proj-sre",      agent_type: "assistant") }
  let!(:deployer) { canonical(name: "Project Deployer", slug: "proj-deployer", agent_type: "code_assistant") }
  let!(:observer) { canonical(name: "Project Observer", slug: "proj-observer", agent_type: "monitor") }

  let(:writer) { Ai::Agents::HierarchyWriter.new(account: account) }

  # The cloning agent's own authority. Everything the project team is granted
  # must be a subset of THIS.
  let(:parent_delegate_types) { %w[assistant code_assistant monitor data_analyst] }
  let(:parent_max_depth)      { 4 }
  let(:parent_budget_pct)     { 0.5 }

  before do
    [ deployer, observer ].each { |child| writer.attach!(child: child, parent: sre, spawn_reason: "seed") }
    writer.ensure_delegation_policy!(
      agent: sre, inheritance_policy: "moderate", max_depth: parent_max_depth,
      allowed_delegate_types: parent_delegate_types, budget_delegation_pct: parent_budget_pct,
      allowed_actions: %w[research deploy observe]
    )
  end

  let!(:template) do
    Ai::Teams::CanonicalTeamSeeder.seed!(
      slug: described_class::TEMPLATE_SLUG,
      name: "Project Operations",
      description: "Observes, deploys and keeps a project up",
      category: "operations",
      members: [
        { slug: "proj-sre",      name: "Project SRE",      role: "manager",  lead: true },
        { slug: "proj-deployer", name: "Project Deployer", role: "executor" },
        { slug: "proj-observer", name: "Project Observer", role: "analyst" }
      ]
    )
  end

  let(:project) { create(:ai_project, account: account, name: "Ledger Service") }

  def provision(target = project) = described_class.provision!(project: target, user: user)

  def clone_of(canonical_agent) = Ai::Agents::AccountPrincipalResolver.existing(canonical_agent, account: account)

  describe "the team it materialises" do
    it "binds a team to the project and seats every template role" do
      result = provision

      expect(result.team).to be_present
      expect(result.created).to be true
      expect(project.reload.team).to eq(result.team)
      expect(result.team.account_id).to eq(account.id)
      expect(result.team.template_id).to eq(template.id)
      expect(result.team.members.count).to eq(3)
      expect(result.team.members.map(&:role)).to match_array(%w[manager executor analyst])
    end

    it "seats ACCOUNT CLONES, never the canonicals, and each carries a lineage row" do
      team = provision.team
      seated = team.members.includes(:agent).map(&:agent)

      # Rows, not counts: no seat is a global canonical.
      expect(seated.map(&:account_id).uniq).to eq([ account.id ])
      expect(seated.map(&:id) & [ sre.id, deployer.id, observer.id ]).to be_empty

      [ sre, deployer, observer ].each do |canonical_agent|
        principal = clone_of(canonical_agent)
        expect(seated).to include(principal)
        expect(principal.cloned_from_id).to eq(canonical_agent.id)
        lineage = Ai::AgentLineage.for_child(principal.id).active
                                  .find_by(parent_agent_id: canonical_agent.id)
        expect(lineage).to be_present, "no active canonical_clone lineage row for #{canonical_agent.slug}"
      end
    end

    it "starts a newly minted principal at the SUPERVISED trust tier" do
      team = provision.team
      tiers = team.members.map { |m| Ai::AgentTrustScore.find_by(agent_id: m.ai_agent_id)&.tier }

      expect(tiers).to all(eq("supervised"))
    end

    it "is idempotent — a second pass creates no second team and no second seat" do
      first = provision.team

      expect { provision }
        .to avoid_changing { account.ai_agent_teams.count }
        .and avoid_changing { Ai::AgentTeamMember.where(ai_agent_team_id: first.id).count }

      expect(project.reload.team).to eq(first)
    end
  end

  describe "a SECOND project" do
    let(:other_project) { create(:ai_project, account: account, name: "Billing Service") }

    it "gets its OWN team, never the first project's" do
      first = provision.team
      second = provision(other_project).team

      expect(second).to be_present
      expect(second.id).not_to eq(first.id)
      expect(other_project.reload.ai_agent_team_id).to eq(second.id)
      expect(project.reload.ai_agent_team_id).to eq(first.id)
      expect(account.ai_agent_teams.count).to eq(2)
    end

    it "reuses the account principals rather than minting a second clone per project" do
      provision
      minted = Ai::Agent.where(account_id: account.id).count

      provision(other_project)

      expect(Ai::Agent.where(account_id: account.id).count).to eq(minted)
    end
  end

  # THE LAUNDERING GUARD, on its own oracle.
  #
  # These examples call the pure narrowing directly, so nothing about clone
  # resolution, template seeding or team seating can fail them. That
  # independence is the point: while the guard could only be reached through
  # the whole provisioning path, breaking the clone lookup also failed the
  # sentinel example, and the example stopped being a unique signal for the
  # guard being gone. Mutation-checked in both directions.
  describe ".narrow_delegate_types" do
    let(:seated) { %w[assistant code_assistant monitor] }

    it "writes the SENTINEL when the intersection is empty, never an empty list" do
      # `[]` is the UNRESTRICTED spelling — see Ai::DelegationPolicy
      # #allows_delegate_type?. Returning it here would turn the narrowing into
      # a grant of everything.
      expect(described_class.narrow_delegate_types(held: %w[data_analyst], seated: seated))
        .to eq([ described_class::NO_SUCH_TYPE_SENTINEL ])
    end

    it "narrows an UNRESTRICTED parent to the seated types instead of copying it" do
      expect(described_class.narrow_delegate_types(held: [], seated: seated)).to match_array(seated)
      expect(described_class.narrow_delegate_types(held: nil, seated: seated)).to match_array(seated)
    end

    it "grants only the intersection — never a type the parent lacked" do
      granted = described_class.narrow_delegate_types(held: %w[assistant monitor data_analyst], seated: seated)

      expect(granted).to match_array(%w[assistant monitor])
      expect(granted).not_to include("code_assistant")
      expect(granted).not_to include("data_analyst")
    end

    it "returns the sentinel when BOTH sides are empty, not an unrestricted grant" do
      expect(described_class.narrow_delegate_types(held: [], seated: []))
        .to eq([ described_class::NO_SUCH_TYPE_SENTINEL ])
    end
  end

  describe ".narrow_delegatable_actions" do
    it "returns the SENTINEL for a parent that declared no actions" do
      # #allows_action? reads blank as unrestricted too.
      expect(described_class.narrow_delegatable_actions(held: []))
        .to eq([ described_class::NO_SUCH_ACTION_SENTINEL ])
    end

    it "keeps exactly what the parent held" do
      expect(described_class.narrow_delegatable_actions(held: %w[deploy observe]))
        .to match_array(%w[deploy observe])
    end
  end

  describe "the delegation policy it writes (permission laundering)" do
    it "grants no delegate type the cloning agent did not hold" do
      team = provision.team
      manager_principal = team.team_lead.agent
      policy = Ai::DelegationPolicy.resolve_for(agent_id: manager_principal.id, account_id: account.id)

      expect(policy).to be_present
      granted = Array(policy.allowed_delegate_types).map(&:to_s)
      expect(granted).not_to be_empty, "an empty list reads as UNRESTRICTED — see the model predicate"
      expect(granted - parent_delegate_types).to be_empty
    end

    it "grants no more depth or budget than the cloning agent held" do
      team = provision.team
      policy = Ai::DelegationPolicy.resolve_for(agent_id: team.team_lead.ai_agent_id, account_id: account.id)

      expect(policy.max_depth).to be <= parent_max_depth
      expect(policy.budget_delegation_pct).to be <= parent_budget_pct
    end

    it "narrows the depth further when the PROJECT declares a tighter bound" do
      project.update!(configuration: { "delegation" => { "max_depth" => 1 } })

      team = provision.team
      policy = Ai::DelegationPolicy.resolve_for(agent_id: team.team_lead.ai_agent_id, account_id: account.id)

      expect(policy.max_depth).to eq(1)
    end

    context "when the cloning agent may delegate to NOTHING the team carries" do
      let(:parent_delegate_types) { %w[data_analyst] }

      it "writes the no-such-type SENTINEL, never an empty list" do
        # THE TRAP: Ai::DelegationPolicy#allows_delegate_type? answers TRUE for a
        # blank list. An intersection that comes out empty must therefore be
        # written as a type nothing carries, or the narrowing becomes a grant of
        # everything.
        team = provision.team
        manager_principal = team.team_lead.agent
        policy = Ai::DelegationPolicy.resolve_for(agent_id: manager_principal.id, account_id: account.id)

        expect(Array(policy.allowed_delegate_types)).to eq([ described_class::NO_SUCH_TYPE_SENTINEL ])
        expect(policy.allows_delegate_type?("code_assistant")).to be false
        expect(policy.allows_delegate_type?("monitor")).to be false
        expect(policy.allows_delegate_type?("assistant")).to be false
      end
    end

    context "when the cloning agent holds an UNRESTRICTED policy" do
      let(:parent_delegate_types) { [] }

      it "does not inherit the unrestricted grant — it narrows to the seated types" do
        team = provision.team
        policy = Ai::DelegationPolicy.resolve_for(agent_id: team.team_lead.ai_agent_id, account_id: account.id)

        granted = Array(policy.allowed_delegate_types).map(&:to_s)
        expect(granted).not_to be_empty
        expect(granted).to match_array(%w[assistant code_assistant monitor])
      end
    end
  end

  # APO app-6 — the outcome must be READABLE afterwards. Best-effort attach was
  # correct and silent; three different teamless situations rendered the same.
  describe "it records WHY there is no team" do
    it "records NO TEMPLATE, naming the template it looked for" do
      template.destroy!

      provision

      status = project.reload.team_provisioning_status

      expect(status[:state]).to eq("no_template")
      expect(status[:template_slug]).to eq(described_class::TEMPLATE_SLUG)
      expect(status[:needs_attention]).to be true
      expect(status[:guidance]).to match(/seed/i)
    end

    it "records FAILED with the error a reader can act on" do
      allow(Ai::Teams::CanonicalTeamReconciler)
        .to receive(:new).and_raise(ActiveRecord::RecordInvalid.new(Ai::AgentTeam.new))

      provision

      status = project.reload.team_provisioning_status

      expect(status[:state]).to eq("failed")
      expect(status[:reason]).to match(/RecordInvalid/)
      expect(status[:needs_attention]).to be true
    end

    it "records NOTHING on success — the team itself is the answer" do
      provision

      expect(project.reload.metadata[Ai::Project::TEAM_PROVISIONING_KEY]).to be_nil
      expect(project.team_provisioning_state).to eq("provisioned")
    end

    it "leaves a project nobody attempted reading as NOT ATTEMPTED" do
      untouched = create(:ai_project, account: account, name: "Never Provisioned")

      expect(untouched.team_provisioning_state).to eq("not_attempted")
    end

    it "clears a stale failure record when a later attempt succeeds" do
      template.destroy!
      provision
      expect(project.reload.team_provisioning_state).to eq("no_template")

      # Re-seed and retry: the team is now ground truth, and the stale record
      # must not keep the project reading as broken.
      Ai::Teams::CanonicalTeamSeeder.seed!(
        slug: described_class::TEMPLATE_SLUG, name: "Project Operations",
        description: "Observes, deploys and keeps a project up", category: "operations",
        materialisation: Ai::Teams::CanonicalTeamSeeder::MATERIALISATION_PROJECT,
        members: [
          { slug: "proj-sre",      name: "Project SRE",      role: "manager",  lead: true },
          { slug: "proj-deployer", name: "Project Deployer", role: "executor" },
          { slug: "proj-observer", name: "Project Observer", role: "analyst" }
        ]
      )
      provision

      expect(project.reload.team_provisioning_state).to eq("provisioned")
      expect(project.team_provisioning_status[:needs_attention]).to be false
    end

    it "still returns a result when RECORDING the reason itself fails" do
      template.destroy!
      allow_any_instance_of(Ai::Project).to receive(:record_team_provisioning!).and_raise(StandardError, "disk full")

      result = nil
      expect { result = provision }.not_to raise_error

      expect(result.team).to be_nil
      expect(project.reload).to be_persisted
    end
  end

  describe "attach is ADDITIVE and best-effort" do
    it "leaves the project valid and usable when the template is absent" do
      template.destroy!

      result = nil
      expect { result = provision }.not_to raise_error

      expect(result.team).to be_nil
      expect(result.skipped).to be_present
      expect(project.reload).to be_persisted
      expect(project.team).to be_nil
      expect(project.status_rollup[:mission_count]).to eq(0)
    end

    it "leaves the project valid when seating raises" do
      allow(Ai::Teams::CanonicalTeamReconciler)
        .to receive(:new).and_raise(ActiveRecord::RecordInvalid.new(Ai::AgentTeam.new))

      result = nil
      expect { result = provision }.not_to raise_error

      expect(result.team).to be_nil
      expect(project.reload.team).to be_nil
      expect(Ai::Project.find_by(id: project.id)).to be_present
    end
  end
end
