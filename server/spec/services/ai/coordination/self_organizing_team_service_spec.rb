# frozen_string_literal: true

require "rails_helper"

# IMP-3af9c533d25d — the service read `capabilities` as an attribute of
# Ai::Agent. There is no such column and no such method. An agent's capabilities
# are its active SKILLS — generate_mcp_tool_manifest builds the manifest's
# "capabilities" from #skill_slugs, which is the platform's own use of the word —
# plus a "capabilities" key in mcp_tool_manifest (that snapshot, which goes
# stale), mcp_metadata or metadata, for agents whose capabilities arrive by
# import. Ai::Agent#declared_capabilities is the single reader over all four, and
# .with_declared_capability its SQL twin — they must agree, or a recruit could
# satisfy a gap the gap analysis still reports.
#
# Each example below is written so that "no longer raises" cannot pass it: every
# one pins a VALUE that depends on the agent half of the vocabulary actually
# being read. A rescue-to-empty implementation fails all of them.
RSpec.describe Ai::Coordination::SelfOrganizingTeamService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:team) { create(:ai_agent_team, account: account) }

  # The factory seeds metadata["capabilities"] = %w[text_generation conversation];
  # every agent here declares its own list so no assertion leans on that default.
  def agent_declaring(capabilities, column: :metadata)
    create(:ai_agent, account: account, status: "active", column => { "capabilities" => capabilities })
  end

  # The live path: capabilities the agent holds as SKILLS, which is what
  # generate_mcp_tool_manifest itself calls the agent's capabilities.
  # Skill slugs are unique per account, so the skill row is shared. Revocation
  # below flips the JOIN row's is_active, which is per-agent, not the skill.
  def agent_skilled_in(slug)
    skill = Ai::Skill.find_by(account: account, slug: slug) || create(:ai_skill, account: account, slug: slug)
    create(:ai_agent, account: account, status: "active", metadata: {}).tap do |agent|
      create(:ai_agent_skill, agent: agent, skill: skill)
    end
  end

  # A manifest cannot be handed to the factory: ensure_mcp_tool_manifest
  # regenerates any manifest missing name/description/type/version, so the
  # fixture would be silently replaced by one whose capabilities are []. Writing
  # it after the fact is also the honest fixture — a materialized manifest that
  # no longer matches the agent's skills is exactly what staleness produces.
  def stale_manifest_capabilities(agent, entries)
    agent.update_column(:mcp_tool_manifest, agent.mcp_tool_manifest.merge("capabilities" => entries))
    agent.reload
  end

  def member_for(agent, capabilities:)
    create(:ai_agent_team_member, team: team, agent: agent, capabilities: capabilities)
  end

  describe "#detect_capability_gap" do
    it "counts the agent's declared capabilities, so a covered requirement is not reported missing" do
      member_for(agent_declaring(%w[ruby]), capabilities: %w[research])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby kubernetes])

      expect(gap[:team_capabilities]).to include("ruby", "research")
      expect(gap[:missing_capabilities]).to eq(%w[kubernetes])
      expect(gap[:gap_detected]).to be(true)
    end

    it "reports no gap when the agent half alone covers every requirement" do
      member_for(agent_declaring(%w[ruby postgres]), capabilities: [])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby postgres])

      expect(gap[:missing_capabilities]).to be_empty
      expect(gap[:gap_detected]).to be(false)
    end

    it "counts a capability the agent holds as a skill" do
      member_for(agent_skilled_in("ruby"), capabilities: [])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby])

      expect(gap[:team_capabilities]).to include("ruby")
      expect(gap[:gap_detected]).to be(false)
    end

    # The manifest is a DERIVED snapshot that nothing refreshes when skills
    # change, so a revoked skill lingers in it forever. Crediting it would make
    # revocation a no-op — the gap analysis, and the recruit that follows it,
    # would keep treating the agent as holding what was taken away.
    it "does not credit a capability the manifest still lists after the skill was revoked" do
      agent = agent_skilled_in("ruby")
      stale_manifest_capabilities(agent, %w[ruby])
      agent.agent_skills.update_all(is_active: false)
      member_for(agent, capabilities: [])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby])

      expect(gap[:team_capabilities]).not_to include("ruby")
      expect(gap[:gap_detected]).to be(true)
    end

    # Once the account has a skill graph the manifest also carries 1-hop
    # NEIGHBOURS at confidence 0.7 — added, per mcp_tool.rb:41, only for slugs
    # the agent does NOT hold. Reading the manifest's entry shape would credit
    # those inferred capabilities as held ones.
    it "does not credit a graph-adjacent capability the agent never held" do
      agent = agent_declaring([])
      stale_manifest_capabilities(agent, [ { "id" => "ruby", "confidence" => 0.7 } ])
      member_for(agent, capabilities: [])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby])

      expect(gap[:team_capabilities]).not_to include("ruby")
      expect(gap[:gap_detected]).to be(true)
    end

    # Independent of the column exclusion above: even in a column that IS read,
    # only bare strings count. {"id" =>, "confidence" =>} is the manifest
    # generator's shape, the one that cannot distinguish a held capability from
    # an inferred one, so it must not be credited wherever it turns up.
    it "does not credit a manifest-shaped entry copied into a column it does read" do
      member_for(agent_declaring([ { "id" => "ruby", "confidence" => 0.7 } ]), capabilities: [])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby])

      expect(gap[:team_capabilities]).not_to include("ruby")
      expect(gap[:gap_detected]).to be(true)
    end

    it "reads capabilities declared in mcp_metadata" do
      member_for(agent_declaring(%w[ruby], column: :mcp_metadata), capabilities: [])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[ruby])

      expect(gap[:team_capabilities]).to include("ruby")
      expect(gap[:gap_detected]).to be(false)
    end

    it "still counts the member half, which the agent half must not displace" do
      member_for(agent_declaring([]), capabilities: %w[research])

      gap = service.detect_capability_gap(team: team, task_requirements: %w[research ruby])

      expect(gap[:team_capabilities]).to eq(%w[research])
      expect(gap[:missing_capabilities]).to eq(%w[ruby])
    end
  end

  describe "#recruit_member!" do
    it "recruits the agent that declares the capability" do
      wanted = agent_declaring(%w[ruby postgres])
      agent_declaring(%w[typescript])

      result = service.recruit_member!(team: team, capability: "ruby")

      expect(result[:recruited]).to be(true)
      expect(result[:agent_id]).to eq(wanted.id)
      member = team.members.find(result[:member_id])
      expect(member.ai_agent_id).to eq(wanted.id)
      expect(member.capabilities).to eq(%w[ruby])
      expect(
        Ai::TeamRestructureEvent.where(team: team, agent: wanted, event_type: "member_recruited")
      ).to exist
    end

    it "recruits an agent whose capability is a skill" do
      wanted = agent_skilled_in("ruby")

      result = service.recruit_member!(team: team, capability: "ruby")

      expect(result[:recruited]).to be(true)
      expect(result[:agent_id]).to eq(wanted.id)
    end

    # Parity between the recruiting SQL and the reading method. If these two
    # disagree, the loop never closes: optimize_team recruits for a gap its own
    # next gap analysis still reports, or refuses to recruit for one it reports.
    it "selects, for every declaration form, exactly the agents the gap analysis credits" do
      credited = {
        "skill" => agent_skilled_in("ruby"),
        "metadata" => agent_declaring(%w[ruby]),
        "mcp_metadata" => agent_declaring(%w[ruby], column: :mcp_metadata)
      }
      # Both halves must REFUSE these identically too: a source only one half
      # excludes is the same defect as a source only one half reads.
      revoked = agent_skilled_in("ruby").tap do |a|
        stale_manifest_capabilities(a, %w[ruby])
        a.agent_skills.update_all(is_active: false)
      end
      excluded = {
        "unrelated capability" => agent_declaring(%w[typescript]),
        "manifest-only (revoked skill)" => revoked,
        "manifest-only (graph-adjacent)" => stale_manifest_capabilities(
          agent_declaring([]), [ { "id" => "ruby", "confidence" => 0.7 } ]
        ),
        "manifest-shaped entry in a read column" => agent_declaring([ { "id" => "ruby", "confidence" => 0.7 } ])
      }

      selected = Ai::Agent.where(account: account).with_declared_capability("ruby").pluck(:id)

      aggregate_failures do
        credited.each do |form, agent|
          expect(selected).to include(agent.id), "#{form}: not selected by with_declared_capability"
          expect(agent.reload.declared_capabilities).to include("ruby"), "#{form}: not read by declared_capabilities"
        end
        excluded.each do |form, agent|
          expect(selected).not_to include(agent.id), "#{form}: wrongly selected by with_declared_capability"
          expect(agent.reload.declared_capabilities).not_to include("ruby"), "#{form}: wrongly read as declared"
        end
      end
    end

    # recruit_member! refuses a blank capability before it gets here, but the
    # scope is public: on its own it must not degenerate into "every agent".
    it "matches nobody when the scope itself is handed a blank capability" do
      agent_declaring(%w[ruby])

      expect(Ai::Agent.where(account: account).with_declared_capability("  ")).to be_empty
    end

    # The inverse oracle: "recruits when the capability is declared" does not
    # prove the filter runs — an unfiltered RANDOM() pick satisfies it whenever
    # the only candidate happens to be the right one.
    it "recruits nobody when no agent declares the capability" do
      agent_declaring(%w[typescript])

      result = service.recruit_member!(team: team, capability: "ruby")

      expect(result).to eq({ recruited: false, reason: "no_suitable_agent" })
      expect(team.members.reload).to be_empty
    end

    it "skips an agent already on the team and takes the free one that declares it" do
      seated = agent_declaring(%w[ruby])
      member_for(seated, capabilities: %w[ruby])
      free = agent_declaring(%w[ruby])

      result = service.recruit_member!(team: team, capability: "ruby")

      expect(result[:recruited]).to be(true)
      expect(result[:agent_id]).to eq(free.id)
    end

    it "ignores agents outside the account and inactive ones" do
      create(:ai_agent, account: create(:account), status: "active", metadata: { "capabilities" => %w[ruby] })
      create(:ai_agent, account: account, status: "inactive", metadata: { "capabilities" => %w[ruby] })

      result = service.recruit_member!(team: team, capability: "ruby")

      expect(result).to eq({ recruited: false, reason: "no_suitable_agent" })
    end

    # Without a capability the old code fell through to an unfiltered RANDOM()
    # pick and then wrote capabilities: [nil], which the member's own validation
    # rejected. Recruiting an arbitrary agent for an unnamed capability is the
    # worse of the two repairs, so this refuses instead.
    it "refuses a blank capability rather than seating an arbitrary agent" do
      agent_declaring(%w[ruby])

      result = service.recruit_member!(team: team, capability: "  ")

      expect(result).to eq({ recruited: false, reason: "capability_required" })
      expect(team.members.reload).to be_empty
    end
  end

  # The real consumer. recruit_agent's own schema marks capability required:true
  # but execute_tool validates no schema, so the blank call arrives at the tool.
  describe "through Ai::Tools::CoordinationTool" do
    let(:user) { create(:user, account: account, permissions: %w[ai.agents.read ai.teams.manage]) }
    let(:tool) { Ai::Tools::CoordinationTool.new(account: account, user: user) }

    it "recruits over the tool surface" do
      wanted = agent_declaring(%w[ruby])

      result = tool.call(action: "recruit_agent", "team_id" => team.id, "capability" => "ruby")

      expect(result[:success]).to be(true)
      expect(result[:data][:recruited]).to be(true)
      expect(team.members.reload.map(&:ai_agent_id)).to eq([ wanted.id ])
    end

    # "recruited: false" is also the legitimate no-candidate outcome, so a
    # malformed call reported through success_result is indistinguishable from a
    # search that simply found nobody.
    it "reports a missing capability as an error, not as a successful non-recruit" do
      agent_declaring(%w[ruby])

      result = tool.call(action: "recruit_agent", "team_id" => team.id)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/capability is required/i)
      expect(team.members.reload).to be_empty
    end
  end

  describe "#evaluate_leader_emergence" do
    it "scores capability breadth over the member's and the agent's declared capabilities" do
      broad = agent_declaring(%w[ruby postgres kubernetes])
      narrow = agent_declaring(%w[ruby])
      member_for(broad, capabilities: %w[research])
      member_for(narrow, capabilities: [])

      scores = service.evaluate_leader_emergence(team: team).index_by { |s| s[:agent_id] }

      expect(scores[broad.id][:breakdown][:capability_breadth]).to eq(0.4)
      expect(scores[narrow.id][:breakdown][:capability_breadth]).to eq(0.1)
    end
  end

  describe "#optimize_team_composition!" do
    it "completes on a team that has members" do
      member_for(agent_declaring(%w[ruby]), capabilities: %w[research])

      expect(service.optimize_team_composition!(team: team))
        .to include(gaps_detected: 0, recruited: 0, released: 0)
    end
  end
end
