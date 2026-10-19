# frozen_string_literal: true

require "rails_helper"

# Streamlining campaign C4: the committed Claude Code skeletons are THIN
# LOADERS for the four survivors (Ai::Agents::CanonicalRoster). A skeleton
# that moved whenever a skill, a prompt or a registered tool changed would need
# a re-sync and a committed diff for every platform edit, and would compete
# with the platform row as the source of truth. The contract this
# pins is the opposite: a skeleton is a pure function of the roster
# declaration, and everything that changes lives behind the bootstrap verbs.
RSpec.describe Ai::ClaudeExport::ThinLoader do
  roster = Ai::Agents::CanonicalRoster

  def frontmatter_of(content)
    _, fm, = content.split(/^---$/, 3)
    YAML.safe_load(fm)
  end

  def tools_of(content)
    frontmatter_of(content)["tools"].split(",").map(&:strip)
  end

  let(:mcp) { ->(action) { "mcp__powernode__platform_#{action}" } }
  let(:bootstrap) { described_class::BOOTSTRAP_ACTIONS.map { |action| mcp.call(action) } }

  it "declares a role for exactly the roster's slugs" do
    expect(described_class::ROLES.keys).to match_array(roster::SLUGS)
  end

  roster::SLUGS.each do |slug|
    describe slug do
      let(:content) { described_class.render(slug) }

      it "carries name, the roster's routing description and model — and nothing else — in its frontmatter" do
        fm = frontmatter_of(content)

        granted = described_class::ROLES.fetch(slug)[:server_grant]
        expect(fm.keys).to eq(%w[name description model tools] + (granted ? %w[disallowedTools] : []))
        expect(fm["name"]).to eq(slug)
        expect(fm["description"]).to eq(roster.fetch(slug)[:description])
        expect(fm["description"]).not_to match(/do not use/i)
        expect(fm["model"]).to eq(Ai::ClaudeExport::AgentSkeletonSync::TIER_TO_CC_MODEL.fetch(roster.fetch(slug)[:tier].to_sym))
      end

      it "lists only the bootstrap core in `tools:`" do
        core = %w[Read Grep Glob ToolSearch Edit Write Bash] + bootstrap + [ described_class::SERVER_GRANT ]

        expect(tools_of(content) - core).to be_empty
        expect(tools_of(content)).to include("Read", "Grep", "Glob", "ToolSearch", *bootstrap)
        expect(tools_of(content).uniq.size).to eq(tools_of(content).size)
      end

      it "stays inside the size budget (MAX_LINES / MAX_BYTES)" do
        expect(content.lines.size).to be <= described_class::MAX_LINES
        expect(content.bytesize).to be <= described_class::MAX_BYTES
      end

      it "bootstraps by slug: charter, skills, tools on demand, the work, then the self-report" do
        body = content.split(/^---$/, 3).last
        order = [
          "mcp__powernode__platform_get_agent` with `slug: \"#{slug}\"`",
          "mcp__powernode__platform_discover_skills",
          "mcp__powernode__platform_discover_tools",
          "mcp__powernode__platform_record_agent_execution` with `agent_slug: \"#{slug}\"`"
        ]

        positions = order.map { |needle| body.index(needle) }
        expect(positions).to all(be_an(Integer))
        expect(positions).to eq(positions.sort)
        expect(body).to include(Ai::ClaudeExport::AgentSkeletonSync::GENERATED_HEADER)
        # The run_key shape .claude/hooks/subagent-report.sh parses back out of the transcript.
        expect(body).to include("run_key: \"<$CLAUDE_CODE_SESSION_ID>:#{slug}:<UTC start time as YYYYMMDDTHHMMSSZ>\"")
      end
    end
  end

  it "gives Edit/Write/Bash and the whole-server grant to the engineer, and keeps the reviewer read-only" do
    engineer = tools_of(described_class.render("platform-engineer"))
    reviewer = tools_of(described_class.render("platform-reviewer"))

    expect(engineer).to include("Edit", "Write", "Bash", described_class::SERVER_GRANT)
    expect(reviewer).not_to include("Edit", "Write", "Bash", described_class::SERVER_GRANT)
    expect(tools_of(described_class.render("powernode-concierge"))).not_to include("Edit", "Write", "Bash")
    expect(tools_of(described_class.render("fleet-operator"))).not_to include("Edit", "Write", "Bash")
  end

  # Mcp::Principal#may_invoke? admits every verb for a session principal, so the
  # whole-server grant would otherwise reach destructive verbs no AutonomyGate
  # check guards. The granted roles deny them by exact name.
  it "denies the ungated destructive verbs to every role holding the whole-server grant" do
    denied = described_class::DENIED_ACTIONS.map { |action| "#{Ai::ClaudeExport::ToolAllowlist::MCP_PREFIX}#{action}" }

    described_class::ROLES.each do |slug, role|
      fm = frontmatter_of(described_class.render(slug))
      if role[:server_grant]
        expect(fm["disallowedTools"].split(",").map(&:strip)).to match_array(denied), slug
      else
        expect(fm).not_to have_key("disallowedTools"), slug
      end
    end
  end

  it "denies every registered destroy-shaped verb that no AutonomyGate declaration can park" do
    ungated = Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |name, klass|
      tool = klass.is_a?(String) ? klass.safe_constantize : klass
      next unless tool.respond_to?(:declared_action)

      declaration = tool.declared_action(name)
      shaped = Mcp::Principal.destructive_tool?(name.to_s) || declaration&.dig(:destructive)
      name.to_s if shaped && !tool.may_park?(declaration)
    end

    expect(ungated - described_class::DENIED_DESTRUCTIVE_ACTIONS).to be_empty
  end

  it "names only registered verbs in DENIED_ACTIONS (a typo would deny nothing)" do
    registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)

    expect(described_class::DENIED_ACTIONS - registered).to be_empty
  end

  it "refuses a slug outside the roster" do
    expect { described_class.render("platform-developer") }.to raise_error(KeyError)
  end

  # THE RESTART CONTRACT. Nothing a platform edit can change reaches the file.
  describe "invariance" do
    let(:baseline) { roster::SLUGS.to_h { |slug| [ slug, described_class.render(slug) ] } }
    let(:rerendered) { roster::SLUGS.to_h { |slug| [ slug, described_class.render(slug) ] } }

    before do
      baseline
      roster::SLUGS.each do |slug|
        spec = roster.fetch(slug)
        create(:ai_agent, :global, is_system: true, slug: slug, name: spec[:name], agent_type: spec[:agent_type])
      end
    end

    it "is unchanged when a skill is bound to a survivor" do
      agent = Ai::Agent.global.find_by!(slug: "platform-engineer")
      create(:ai_agent_skill, agent: agent, skill: create(:ai_skill, :global, slug: "engineer-release"), is_active: true)

      expect(rerendered).to eq(baseline)
    end

    it "is unchanged when a survivor's prompt or description is edited" do
      Ai::Agent.global.where(slug: roster::SLUGS).find_each do |agent|
        agent.update!(system_prompt: "an operator's new charter", description: "Something else entirely.")
      end

      expect(rerendered).to eq(baseline)
    end

    it "is unchanged when a tool is registered" do
      tools = Ai::Tools::PlatformApiToolRegistry.all_tools.merge("discover_tools" => "Ai::Tools::ToolCatalogTool",
                                                                 "brand_new_verb" => "Ai::Tools::ToolCatalogTool")
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools).and_return(tools)

      expect(rerendered).to eq(baseline)
    end

    it "is unchanged when another canonical agent is seeded" do
      create(:ai_agent, :global, is_system: true, name: "Yet Another Specialist")

      expect(rerendered).to eq(baseline)
    end
  end
end
