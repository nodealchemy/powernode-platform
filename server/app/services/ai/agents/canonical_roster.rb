# frozen_string_literal: true

module Ai
  module Agents
    # THE target canonical roster (streamlining campaign C4,
    # docs/operations/streamlining-review-2026-10-19.md §4.1): four agents that
    # discover skills and tools on demand instead of carrying a persona and a
    # tool list per duty. Two consumers read this and nothing else, so they
    # cannot disagree about who the survivors are:
    #   * db/seeds/ai_canonical_agents_seed.rb — the global canonical rows;
    #   * Ai::ClaudeExport::AgentSkeletonSync — the committed Claude Code
    #     skeletons, which are exactly these slugs.
    #
    # SHADOW MODE. The survivors are seeded BESIDE the 28 canonicals they will
    # absorb (`absorbs`, informational until the re-home step) and those keep
    # running the platform: lanes, policies, approval chains, SIGNAL_BINDINGS
    # owners, PLATFORM_AGENT_DEFAULT_SLUG and CORE_CANONICAL_KEYS are untouched.
    #
    # `description` is the routing sentence on both sides (the platform row and
    # the skeleton's frontmatter): broad, and non-overlapping by construction —
    # the platform itself, the running fleet, reviewing finished work, and
    # everything else (the front door). `tier` is the declared model tier
    # (mcp_metadata.model_config.model_requirements.tier); the export maps it
    # to the frontmatter `model:`.
    module CanonicalRoster
      SURVIVORS = {
        "powernode-concierge" => {
          name: "Powernode Concierge",
          agent_type: "assistant",
          tier: "standard",
          description: "The front door for any Powernode request that is not yet a defined engineering, fleet or " \
                       "review task: answers questions about the platform, onboards, captures provisioning " \
                       "briefs, and routes the work to the agent or skill that owns it.",
          absorbs: %w[powernode-assistant system-concierge]
        },
        "platform-engineer" => {
          name: "Platform Engineer",
          agent_type: "code_assistant",
          tier: "standard",
          description: "Changes the Powernode platform itself: code, specs, docs, releases, campaigns and " \
                       "knowledge. Use it to implement dev-improve tasks and campaign increments, keep docs " \
                       "truthful, cut and promote releases, and research or curate what lands in the repo.",
          absorbs: %w[
            platform-architect platform-developer release-manager documentation-specialist
            research-analyst strategic-planner prd-generator knowledge-graph-curator
          ]
        },
        "fleet-operator" => {
          name: "Fleet Operator",
          agent_type: "monitor",
          tier: "standard",
          description: "Operates the running Powernode fleet: nodes, instances, capacity, storage, networking, " \
                       "ingress, runtimes, disk images, packages and CVEs — inspects live state and takes " \
                       "operational actions through the platform's gated verbs.",
          absorbs: %w[
            fleet-autonomy capacity-manager storage-manager ingress-manager sdwan-manager runtime-manager
            disk-image-manager gitops-reconciler supply-chain-manager cve-responder system-topology-designer
          ]
        },
        "platform-reviewer" => {
          name: "Platform Reviewer",
          agent_type: "assistant",
          tier: "reasoning",
          description: "Independent, read-only review of finished work — a drained task's diff, a campaign " \
                       "increment, a doc change or an autonomy decision — judged against its acceptance " \
                       "criteria. Never reviews work it produced.",
          absorbs: %w[llm-judge system-quality-assurance]
        }
      }.freeze

      SLUGS = SURVIVORS.keys.freeze

      module_function

      # @return [Hash] the survivor's declaration; raises KeyError for any other slug
      def fetch(slug)
        SURVIVORS.fetch(slug.to_s)
      end

      def include?(slug)
        SURVIVORS.key?(slug.to_s)
      end
    end
  end
end
