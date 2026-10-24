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

  def role_of(slug) = Ai::Agents::CanonicalRoster.fetch(slug)[:role]

  it "reads each agent's role from its roster spec (no second table to drift)" do
    expect(described_class.constants).not_to include(:ROLES)
    roster.slugs.each { |slug| expect(role_of(slug).keys - [ :shell_guard ]).to match_array(%i[code shell server_grant read_only verbs duty]), slug }
  end

  roster.slugs.each do |slug|
    describe slug do
      let(:content) { described_class.render(slug) }

      it "carries name, the roster's routing description and model — and nothing else — in its frontmatter" do
        fm = frontmatter_of(content)

        granted = role_of(slug)[:server_grant]
        expect(fm.keys).to eq(%w[name description model tools] + (granted ? %w[disallowedTools] : []) + (role_of(slug)[:shell_guard] ? %w[hooks] : []))
        expect(fm["name"]).to eq(slug)
        expect(fm["description"]).to eq(roster.fetch(slug)[:description])
        expect(fm["description"]).not_to match(/do not use/i)
        expect(fm["model"]).to eq(Ai::ClaudeExport::AgentSkeletonSync::TIER_TO_CC_MODEL.fetch(roster.fetch(slug)[:tier].to_sym))
      end

      it "lists only the bootstrap core in `tools:`" do
        core = %w[Read Grep Glob ToolSearch Edit Write Bash] + bootstrap + [ described_class::SERVER_GRANT ] +
               role_of(slug)[:verbs].map { |verb| mcp.call(verb) }

        expect(tools_of(content) - core).to be_empty
        expect(tools_of(content)).to include("Read", "Grep", "Glob", "ToolSearch", *bootstrap)
        expect(tools_of(content).uniq.size).to eq(tools_of(content).size)
      end

      it "stays inside the size budget (MAX_LINES / MAX_BYTES)" do
        expect(content.lines.size).to be <= described_class::MAX_LINES
        expect(content.bytesize).to be <= described_class::MAX_BYTES
      end

      it "bootstraps by slug: charter, assembly, tools on demand, the work, then the self-report" do
        body = content.split(/^---$/, 3).last
        order = [
          "mcp__powernode__platform_get_agent` with `slug: \"#{slug}\"`",
          "mcp__powernode__platform_assemble_task",
          "describe_tool",
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

  it "gives Edit/Write/Bash and the whole-server grant to the engineer, and the reviewer no shell (phase 1)" do
    engineer = tools_of(described_class.render("platform-engineer"))
    reviewer = tools_of(described_class.render("platform-reviewer"))

    expect(engineer).to include("Edit", "Write", "Bash", described_class::SERVER_GRANT)
    # The read-only shell guard can fail open (frontmatter hooks need workspace
    # trust; an unset $CLAUDE_PROJECT_DIR exits 127, non-blocking), so the
    # reviewer gets no Bash at all: it reads with Read/Grep/Glob.
    expect(reviewer).not_to include("Bash", "Edit", "Write", described_class::SERVER_GRANT)
    expect(frontmatter_of(described_class.render("platform-reviewer"))).not_to have_key("hooks")
    expect(described_class.render("platform-reviewer")).to match(/you have no shell/i)
    # Every registered role without code/shell (core's concierge, an extension's operator): no Edit/Write/Bash.
    roster.slugs.reject { |slug| role_of(slug)[:code] || role_of(slug)[:shell] }.each do |slug|
      expect(tools_of(described_class.render(slug))).not_to include("Edit", "Write", "Bash"), slug
    end
  end

  # Mcp::Principal#may_invoke? admits every verb for a session principal, so the
  # whole-server grant would otherwise reach destructive verbs no AutonomyGate
  # check guards. The granted roles deny them by exact name.
  it "denies the ungated destructive verbs to every role holding the whole-server grant" do
    denied = described_class::DENIED_ACTIONS.map { |action| "#{Ai::ClaudeExport::ToolAllowlist::MCP_PREFIX}#{action}" }

    roster.slugs.each do |slug|
      fm = frontmatter_of(described_class.render(slug))
      if role_of(slug)[:server_grant]
        expect(fm["disallowedTools"].split(",").map(&:strip)).to match_array(denied), slug
      else
        expect(fm).not_to have_key("disallowedTools"), slug
      end
    end
  end

  # Resolved through ToolDeclarationCoverage, the shared resolver that mirrors
  # BaseTool#execute's alias hop: a lookup by the raw registry key finds the
  # wrong (or no) declaration for an aliased entry (prune_stale vs code_prune_stale).
  def registry_rows
    Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |name, klass|
      tool = klass.is_a?(String) ? klass.safe_constantize : klass
      next unless tool.respond_to?(:declared_action)

      action = ToolDeclarationCoverage.resolved_action_name(name, tool)
      { name: name.to_s, tool: tool, declaration: tool.declared_action(action) }
    end
  end

  it "denies every registered destroy-shaped verb that no AutonomyGate declaration can park" do
    ungated = registry_rows.filter_map do |row|
      shaped = Mcp::Principal.destructive_tool?(row[:name]) || row[:declaration]&.dig(:destructive)
      row[:name] if shaped && !row[:tool].may_park?(row[:declaration])
    end

    expect(ungated - described_class::DENIED_DESTRUCTIVE_ACTIONS).to be_empty
  end

  # The other direction: a verb a declaration can now park is dropped from the
  # denied list in the same change, so the list only ever holds what is still
  # ungated (emergency_halt is the deliberate exemption, see below).
  it "lists in DENIED_DESTRUCTIVE_ACTIONS only verbs that are still ungated" do
    gated = registry_rows.filter_map do |row|
      row[:name] if described_class::DENIED_DESTRUCTIVE_ACTIONS.include?(row[:name]) &&
                    row[:tool].may_park?(row[:declaration])
    end

    expect(gated).to be_empty
  end

  # emergency_halt is the one destroy-shaped verb a decision keeps OUTSIDE the
  # gate: it must act at once for a human session, so it never parks, and agents
  # stay denied it by name. Its exemption is a named constant, not an omission.
  it "records the deliberate exemption: UNGATED_BY_DECISION verbs are denied to agents and really cannot park" do
    exempt = described_class::UNGATED_BY_DECISION
    expect(exempt).to match_array(%w[emergency_halt approve_deferred_operation reject_deferred_operation])
    expect(exempt - described_class::DENIED_DESTRUCTIVE_ACTIONS).to be_empty

    registry_rows.select { |row| exempt.include?(row[:name]) }.each do |row|
      expect(row[:tool].may_park?(row[:declaration])).to be(false), row[:name]
    end
    expect(registry_rows.map { |row| row[:name] } & exempt).to eq(exempt)
  end

  it "names only registered verbs in DENIED_ACTIONS (a typo would deny nothing)" do
    registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)

    expect(described_class::DENIED_ACTIONS - registered).to be_empty
  end

  it "names only verbs of the platform's own bootstrap floor (each one registered)" do
    floor = Ai::ClaudeExport::ToolAllowlist::BOOTSTRAP_ACTIONS
    registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)

    expect(described_class::BOOTSTRAP_ACTIONS - floor).to be_empty
    expect(described_class::BOOTSTRAP_ACTIONS - registered).to be_empty
  end

  describe "the assembly bootstrap" do
    roster.slugs.each do |slug|
      it "#{slug}: step 2 is assemble_task (with the assembly_id from the prompt), step 5 passes assembly_id, no manifest mode" do
        content = described_class.render(slug)
        body = content.split(/^---$/, 3).last

        expect(body).to include("mcp__powernode__platform_assemble_task")
        expect(body).to match(/`assembly_id` from your prompt/)
        expect(body).to match(/record_agent_execution.*`assembly_id`/m)
        expect(body).not_to include("manifest")
        expect(body).not_to include("get_skill_context")
        expect(tools_of(content)).to include("mcp__powernode__platform_assemble_task")
      end

      it "#{slug}: a missing get_agent row tells the driver exactly what to do" do
        body = described_class.render(slug).split(/^---$/, 3).last

        step1 = body.lines.find { |l| l.start_with?("1. Charter:") }

        expect(step1).to include("do not proceed under a generic identity")
        expect(step1).to include("not seeded on this connector")
        expect(step1).to include("stop and report it to the driver")
        expect(step1).to include("general-purpose")
        # record_agent_execution refuses a slug with no agent row, so step 1 must
        # not send the agent to the report step (the old dead end).
        expect(step1).not_to include('outcome: "failed"')
        expect(step1).not_to include("run step 5 with")
        expect(step1).to include("Do not run step 5")
      end
    end
  end

  # scripts/check-claude-agents-fresh.sh carries an extension-owned skeleton over
  # when its extension is absent (core mode); this marker is how it knows the owner.
  it "marks an extension-owned skeleton with its owner, and a core one not at all" do
    Ai::Agents::CanonicalRoster.each do |slug, _spec, owner|
      body = described_class.render(slug).split(/^---$/, 3).last
      if owner == Ai::Agents::CanonicalRoster::CORE_OWNER
        expect(body).not_to include("<!-- owner:"), slug
      else
        expect(body.lines.map(&:chomp)).to include("<!-- owner: #{owner} -->"), slug
      end
    end
  end

  it "refuses a slug outside the roster" do
    expect { described_class.render("platform-developer") }.to raise_error(KeyError)
  end

  # THE RESTART CONTRACT. Nothing a platform edit can change reaches the file.
  describe "invariance" do
    let(:baseline) { roster.slugs.to_h { |slug| [ slug, described_class.render(slug) ] } }
    let(:rerendered) { roster.slugs.to_h { |slug| [ slug, described_class.render(slug) ] } }

    before do
      baseline
      roster.slugs.each do |slug|
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
      Ai::Agent.global.where(slug: roster.slugs).find_each do |agent|
        agent.update!(system_prompt: "an operator's new charter", description: "Something else entirely.")
      end

      expect(rerendered).to eq(baseline)
    end

    it "is unchanged when a tool is registered" do
      tools = Ai::Tools::PlatformApiToolRegistry.all_tools.merge("brand_new_verb" => "Ai::Tools::ToolCatalogTool")
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools).and_return(tools)

      expect(rerendered).to eq(baseline)
    end

    it "is unchanged when another canonical agent is seeded" do
      create(:ai_agent, :global, is_system: true, name: "Yet Another Specialist")

      expect(rerendered).to eq(baseline)
    end
  end
end
