# frozen_string_literal: true

module Ai
  module Agents
    # THE canonical roster, as a REGISTRY (skills-first agents, PRE-2): who the
    # platform's canonical agents are, declared once, read by everything that
    # needs the list so none of them can disagree:
    #   * db/seeds/ai_canonical_agents_seed.rb and an extension's own agent seed
    #     (both through db/seeds/concerns/canonical_roster_seeder.rb);
    #   * Ai::ClaudeExport::AgentSkeletonSync and ThinLoader — the committed
    #     Claude Code skeletons are exactly the registered slugs, so a core-mode
    #     install exports three and a system-enabled one four;
    #   * Ai::Assembly::Service — the agent's tier floor and domain ceiling.
    #
    # Core declares only ITS agents (below). An extension registers its own from
    # its engine (`register(slug, spec, owner: "extensions/<slug>")`), so core
    # never names an extension's agent. A spec is:
    #
    #   name, agent_type, description (the routing sentence, platform row and
    #   skeleton frontmatter alike), tier (light|standard|reasoning|frontier — the
    #   roster FLOOR; assembly only raises it), domains (the skill-domain ceiling),
    #   role { code: Edit/Write/Bash, shell: Bash alone, server_grant: the
    #   whole-server MCP grant, shell_guard (optional; REQUIRED for a shell without
    #   code): the PreToolUse hook file rendered into the skeleton's own frontmatter
    #   to keep that shell read-only, read_only: the role may only be assembled with
    #   read-only skills (manifest.read_only), verbs: the exact verbs a role
    #   WITHOUT the whole-server grant may call beyond the bootstrap floor —
    #   those its assemblable skills name (loader_verb_coverage_spec keeps the two
    #   in step) — and duty: the skeleton's one duty sentence },
    #   charter (the assembly prompt, at most MAX_CHARTER_LINES lines: identity,
    #   assembly protocol, role duty, escalation rule, report rule — no domain
    #   knowledge; domain knowledge is skills), posture { trust:, chain_approvers: }
    #   (create-only seed bootstrap).
    #
    # SHADOW MODE is unchanged: the rows are seeded INACTIVE beside the legacy
    # canonicals (db/seeds/ai_canonical_agents_seed.rb).
    module CanonicalRoster
      CORE_OWNER = "core"
      TIERS = %w[light standard reasoning frontier].freeze
      REQUIRED_KEYS = %i[name agent_type description tier domains role charter].freeze
      ROLE_KEYS = %i[code shell server_grant read_only verbs duty].freeze
      MAX_CHARTER_LINES = 25

      class DuplicateSlug < StandardError; end

      # Ordered slug => [spec, owner]. Public so a spec can build an isolated one.
      class Registry
        def initialize
          @entries = {}
        end

        def register(slug, spec, owner:)
          slug = slug.to_s
          existing = @entries[slug]
          if existing && existing[:owner] != owner.to_s
            raise DuplicateSlug, "#{slug} is already registered by #{existing[:owner]}"
          end

          @entries[slug] = { spec: validate!(slug, spec).freeze, owner: owner.to_s }
          self
        end

        def each(owner = nil)
          return to_enum(:each, owner) unless block_given?

          @entries.each do |slug, entry|
            yield slug, entry[:spec], entry[:owner] if owner.nil? || entry[:owner] == owner.to_s
          end
        end

        def fetch(slug) = @entries.fetch(slug.to_s)[:spec]
        def slugs = @entries.keys
        def include?(slug) = @entries.key?(slug.to_s)

        private

        def validate!(slug, spec)
          spec = spec.to_h.symbolize_keys
          missing = REQUIRED_KEYS - spec.keys
          raise ArgumentError, "#{slug}: roster spec is missing #{missing.join(', ')}" if missing.any?
          raise ArgumentError, "#{slug}: tier #{spec[:tier].inspect} is not one of #{TIERS.join('/')}" unless TIERS.include?(spec[:tier].to_s)
          raise ArgumentError, "#{slug}: domains must be a non-empty list" unless spec[:domains].is_a?(Array) && spec[:domains].any?

          role = spec[:role].to_h.symbolize_keys
          raise ArgumentError, "#{slug}: role needs #{ROLE_KEYS.join(', ')}" unless (ROLE_KEYS - role.keys).empty?
          raise ArgumentError, "#{slug}: role verbs must be a list of verb names" unless role[:verbs].is_a?(Array)
          raise ArgumentError, "#{slug}: a role with the whole-server grant lists no explicit verbs" if role[:server_grant] && role[:verbs].any?
          # A shell without Edit/Write is only "read-only" if something enforces it.
          if role[:shell] && !role[:code] && role[:shell_guard].to_s.empty?
            raise ArgumentError, "#{slug}: a shell role without code needs a shell_guard hook (.claude/hooks/<name>.sh) that enforces read-only"
          end

          lines = spec[:charter].to_s.lines.count { |l| l.strip.present? }
          raise ArgumentError, "#{slug}: charter is #{lines} lines (max #{MAX_CHARTER_LINES})" if lines > MAX_CHARTER_LINES

          spec.merge(role: role.merge(verbs: role[:verbs].map(&:to_s).freeze).freeze, posture: (spec[:posture] || {}).freeze, tier: spec[:tier].to_s, domains: spec[:domains].map(&:to_s).freeze)
        end
      end

      module_function

      def registry
        @registry ||= Registry.new
      end

      def register(slug, spec, owner:) = registry.register(slug, spec, owner: owner)

      # @yieldparam slug, spec, owner — registration order; without a block, an Enumerator
      def each(owner: nil, &block) = registry.each(owner, &block)

      # @return [Hash] the declaration; raises KeyError for any unregistered slug
      def fetch(slug) = registry.fetch(slug)
      def include?(slug) = registry.include?(slug)
      def slugs = registry.slugs

      # The assembly prompt every canonical agent carries: identity sentence,
      # assembly protocol, role duty, escalation rule, report rule. Domain
      # knowledge is NOT here — it is the skills the assembly returns.
      #
      # @param identity [String] one or two sentences: who this agent is
      # @param duty [String] the role duty (what this agent must never do / always do)
      def assembly_charter(identity:, duty:)
        <<~CHARTER.strip
          #{identity}

          ## How you work
          1. Assemble first: call `assemble_task` with the `assembly_id` from your prompt (or with your task and
             your slug if there is none). Adopt the returned skills, learnings and verb lists as your working
             method; they, not this prompt, carry the domain knowledge.
          2. Load only the verbs the assembled skills name (`describe_tool` each before its first call); never
             scan the catalog. Every verb is gated by the platform: read the returned status, never retry
             around a parked action.
          3. Duty: #{duty}
          4. Escalate: work outside the assembled skills or outside your charter goes back through `route_task`
             (or to the delegating session) with what you tried; do not improvise it.
          5. Report: finish with `record_agent_execution` under your own slug, passing the `assembly_id`.
        CHARTER
      end

      register(
        "powernode-concierge",
        {
          name: "Powernode Concierge",
          agent_type: "assistant",
          tier: "standard",
          description: "The front door for any Powernode request that is not yet a defined engineering, fleet or " \
                       "review task: answers questions about the platform, onboards, captures provisioning " \
                       "briefs, and routes the work to the agent or skill that owns it.",
          domains: %w[front-door knowledge external-agent-session],
          role: { code: false, shell: false, server_grant: false, read_only: false,
                  # Exactly the verbs the front-door, knowledge (read and contribute) and
                  # external-session skills name. The curation verbs live in skills of the
                  # knowledge-curation domain, outside this role's ceiling.
                  verbs: %w[
                    create_knowledge create_learning dispute_learning get_conversation_messages get_skill_context
                    invite_agent knowledge_health learning_metrics list_agents list_messages list_workspaces
                    platform_provisioning_capture_brief platform_provisioning_status rate_knowledge reinforce_learning
                    search_knowledge_graph send_message
                  ],
                  duty: "Answer and route: never execute fleet or code writes yourself." },
          charter: assembly_charter(
            identity: "You are the **Powernode Concierge**, the platform's front door: you answer questions, " \
                      "onboard operators and capture briefs, then hand work to the agent that owns it.",
            duty: "answer and route; you never execute fleet or code writes yourself."
          ),
          posture: { trust: { tier: "trusted", overall: 0.85,
                              dimensions: { reliability: 0.85, cost_efficiency: 0.80, safety: 0.90, quality: 0.80, speed: 0.80 } } }
        },
        owner: CORE_OWNER
      )

      register(
        "platform-engineer",
        {
          name: "Platform Engineer",
          agent_type: "code_assistant",
          tier: "standard",
          description: "General software engineer for the platform and the projects built on it: code, specs, docs, " \
                       "releases, campaigns and knowledge. Use it to implement dev-improve tasks and campaign " \
                       "increments, keep docs truthful, cut and promote releases, and research or curate what " \
                       "lands in the repo. It builds and releases; it never deploys.",
          domains: ::Ai::Skills::Contract::CORE_DOMAINS - %w[front-door],
          role: { code: true, shell: true, server_grant: true, read_only: false, verbs: [],
                  duty: "Edit only in the worktree and branch the prompt names, red first, and commit only when it says so." },
          charter: assembly_charter(
            identity: "You are the **Platform Engineer**, a general software engineer: you change code, specs, docs " \
                      "and releases, for this platform and for the projects built on it.",
            duty: "edit only in the worktree and branch the prompt names, red first, commit only when it says so; " \
                  "a deploy is never yours: hand it, through `route_task`, to the agent that operates the " \
                  "running fleet; you cannot spawn a reviewer, so report your diff for independent review."
          ),
          posture: { trust: { tier: "monitored", overall: 0.58,
                              dimensions: { reliability: 0.60, cost_efficiency: 0.70, safety: 0.84, quality: 0.58, speed: 0.66 } },
                     chain_approvers: [ { "type" => "permission", "value" => "ai.autonomy.approve" } ] }
        },
        owner: CORE_OWNER
      )

      register(
        "platform-reviewer",
        {
          name: "Platform Reviewer",
          agent_type: "assistant",
          tier: "reasoning",
          description: "Independent, read-only review of finished work — a drained task's diff, a campaign " \
                       "increment, a doc change or an autonomy decision — judged against its acceptance " \
                       "criteria. Never reviews work it produced.",
          domains: %w[review knowledge],
          # Phase 1: NO shell. .claude/hooks/readonly-shell-guard.sh can fail open (a
          # frontmatter hook needs workspace trust; an unset $CLAUDE_PROJECT_DIR is a
          # non-blocking exit 127), so the reviewer reads and the delegating session
          # runs any command the review needs.
          role: { code: false, shell: false, server_grant: false, read_only: true,
                  # Read-only verbs only (the review skills that are manifest.read_only name these).
                  verbs: %w[code_blast_radius code_file_skeleton code_semantic_search code_static_analysis list_audit_logs],
                  duty: "You are read-only and you have no shell: read the diff and files with Read, Grep and Glob " \
                        "and the read-only code verbs; name any check that needs a command run (git, tests) in " \
                        "your report for the delegating session to run. Never edit, commit or call a mutating " \
                        "verb, and never review work you produced." },
          charter: assembly_charter(
            identity: "You are the **Platform Reviewer**: the independent review of finished work against its " \
                      "acceptance criteria, reported by severity with file and line, then a verdict.",
            duty: "you are read-only and have no shell: read with Read, Grep, Glob and the read-only code verbs, " \
                  "and name any check that needs a command (git, tests) in your report for the delegating " \
                  "session to run. Never edit, commit or call a mutating verb, and never review work you produced."
          ),
          posture: {}
        },
        owner: CORE_OWNER
      )
    end
  end
end
