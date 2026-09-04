# frozen_string_literal: true

module Ai
  module ClaudeExport
    # REVERSE PATH AS PROPOSAL (HIER-P1B item 6). Reads hand-authored Claude
    # Code agent files (`.claude/agents/**/*.md` WITHOUT the generated header)
    # and files one Ai::AgentProposal (proposal_type "agent_create") per file,
    # whose payload is the would-be CANONICAL spec. Nothing is created directly:
    # official agents are seeded canonicals and the platform is the source of
    # truth (canonical rule + guidance-agent-escalation), so a Claude Code
    # author proposes and an operator decides.
    #
    # Attribution: the Platform Architect agent when the account can resolve
    # one (override-aware, by slug then name), else the account's concierge —
    # a proposal needs an authoring agent (Ai::AgentProposal belongs_to :agent).
    #
    # Field mapping (inverse of AgentSkeletonSync where one exists):
    #   frontmatter name         -> slug (+ titleized name)
    #   frontmatter description  -> description
    #   frontmatter agent_type   -> agent_type (default "assistant")
    #   body                     -> system_prompt
    #   frontmatter tools        -> tool_access.tool_families (mcp__powernode__
    #                               platform_<action> entries only; CC built-ins
    #                               have no platform counterpart and are dropped;
    #                               an exact action name IS a valid family entry)
    #   frontmatter model        -> model_config.model_requirements.tier
    #                               (inverse of TIER_TO_CC_MODEL)
    class AgentImportProposer
      ARCHITECT_SLUG = "platform-architect"
      ARCHITECT_NAME = "Platform Architect"
      DEFAULT_AGENT_TYPE = "assistant"
      PROPOSAL_TYPE = "agent_create"
      CC_MODEL_TO_TIER = AgentSkeletonSync::TIER_TO_CC_MODEL.invert.transform_values(&:to_s).freeze

      Outcome = Struct.new(:proposals, :skipped, keyword_init: true)

      def initialize(account:, path:)
        @account = account
        @path = Pathname.new(path)
      end

      def propose!
        author = attributed_agent
        raise ArgumentError, "no attributing agent: account #{@account.id} has neither a #{ARCHITECT_NAME} nor a concierge" unless author

        proposals = []
        skipped = []
        agent_files.each do |file|
          spec = parse(file)
          if spec.nil?
            skipped << file.basename.to_s
            next
          end

          proposals << ::Ai::AgentProposal.create!(
            account: @account,
            agent: author,
            title: "Create canonical agent: #{spec['name']}"[0, 255],
            description: "Proposed from the hand-authored Claude Code agent file #{file.basename} via " \
                         "claude:import_agents. Approving does not create the agent; it queues the spec for " \
                         "seeding as a GLOBAL canonical.",
            proposal_type: PROPOSAL_TYPE,
            status: "pending_review",
            priority: "medium",
            proposed_changes: spec,
            impact_assessment: { "source" => "claude:import_agents", "path" => file.to_s }
          )
        end

        Outcome.new(proposals: proposals, skipped: skipped)
      end

      private

      def agent_files
        return [ @path ] if @path.file?

        @path.glob("**/*.md").sort
      end

      # nil for a generated file, a file without frontmatter, or one without a name.
      def parse(file)
        raw = file.read
        return nil if raw.include?(AgentSkeletonSync::GENERATED_HEADER)

        match = raw.match(/\A---\s*\n(?<fm>.*?)\n---\s*\n(?<body>.*)\z/m)
        return nil unless match

        frontmatter = YAML.safe_load(match[:fm]) rescue nil
        return nil unless frontmatter.is_a?(Hash)

        slug = frontmatter["name"].to_s.strip.parameterize
        return nil if slug.blank?

        {
          "slug" => slug,
          "name" => slug.tr("-", " ").titleize,
          "agent_type" => frontmatter["agent_type"].to_s.presence || DEFAULT_AGENT_TYPE,
          "description" => frontmatter["description"].to_s.strip,
          "system_prompt" => match[:body].strip,
          "tool_access" => { "tool_families" => platform_actions_from(frontmatter["tools"]) },
          "model_config" => { "model_requirements" => { "tier" => tier_from(frontmatter["model"]) } },
          "source_file" => file.basename.to_s
        }
      end

      def platform_actions_from(tools)
        entries = tools.is_a?(Array) ? tools : tools.to_s.split(",")
        entries.map(&:to_s).map(&:strip)
               .select { |t| t.start_with?(ToolAllowlist::MCP_PREFIX) }
               .map { |t| t.delete_prefix(ToolAllowlist::MCP_PREFIX) }
               .uniq
      end

      def tier_from(model)
        CC_MODEL_TO_TIER.fetch(model.to_s.strip.downcase, ::Ai::ModelTiers::DEFAULT_TIER.to_s)
      end

      def attributed_agent
        ::Ai::Agent.resolve_for(@account.id, slug: ARCHITECT_SLUG) ||
          ::Ai::Agent.resolve_for(@account.id, name: ARCHITECT_NAME) ||
          ::Ai::Agent.resolve_concierge_for(@account.id)
      end
    end
  end
end
