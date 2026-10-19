# frozen_string_literal: true

module Ai
  module InterventionPolicies
    # Core's own intervention-policy domains, registered with
    # Ai::ClaudeExport::PolicyDomains at boot (config/initializers/core_policy_domains.rb)
    # exactly as an extension registers its table. Before this, only extensions
    # registered domains, so every core category (dev.*, docs.*, release.* and
    # the agent-outreach verbs) fell into the grouped view's catch-all "other"
    # section of the intervention-policy panel.
    #
    # Prefix match, first match wins, in registration order — the same rule
    # GroupedView and PolicyDomains#domain_for apply. Core names only its own
    # namespaces here (Extension Isolation): extension-owned categories stay in
    # the owning extension's table.
    module CorePolicyDomains
      PREFIXES = {
        # Changes to governance itself and to platform settings; "*" is the
        # account-wide default row. `ai.` is a core-owned namespace: core
        # registers first, so an extension must not declare `ai.*` categories.
        # `dev.campaign_propose` (proposing new work from a governance gap) is
        # claimed here, AHEAD of improvement_loop's `dev.`: it is what the
        # Platform Architect does, and filing it under the improvement loop made
        # the exported routing descriptions send loop work away from the
        # Platform Developer.
        "governance"       => %w[dev.campaign_propose ai. platform.site_setting. *],
        # The improvement loop and the engineering agents' own changes.
        "improvement_loop" => %w[dev. docs. ralph. campaign.],
        # Building, deploying, promoting and rolling back the platform.
        "release"        => %w[release.],
        # Messages an agent sends a person (Ai::AgentOutreachService and the
        # autonomy approval path): asking for a decision, escalating, reporting.
        # Bare verbs by design — they are whole category names, not prefixes of
        # a family.
        "agent_outreach" => %w[approval escalation feedback issue_alert proposal status_update]
      }.freeze

      # Registers each domain once. Idempotent so a code-reload prepare cycle
      # that kept the registry (PolicyDomains is a module ivar) does not append
      # a second copy.
      def self.register!
        registered = ::Ai::ClaudeExport::PolicyDomains.registered.map(&:first)
        PREFIXES.each do |domain, prefixes|
          next if registered.include?(domain)

          ::Ai::ClaudeExport::PolicyDomains.register(domain, prefixes)
        end
      end
    end
  end
end
