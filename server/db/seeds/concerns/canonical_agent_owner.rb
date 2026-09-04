# frozen_string_literal: true

# Owner columns (creator, provider) of a GLOBAL canonical agent, filled in on a
# later re-seed.
#
# IMP-6cda93db7f31 made both columns nullable on a global row so the canonical
# seeds no longer need an account, an admin user or a provider to run. The
# corollary is this: `Ai::Agent.find_or_create_global`'s block is CREATE-ONLY
# (GloballyScopable#find_or_create_global), so a canonical first written on a
# fresh core/prod database — before first-admin bootstrap — would keep
# creator_id and ai_provider_id NULL FOREVER, and a provider-less canonical is
# the row every nil-provider reader then has to defend against (the Claude Code
# export's model tier falls back to the default, the clone doors have to
# resolve a provider of their own, the executor's telemetry has to nil-guard).
# The columns therefore fill in on the next re-seed, which is the run right
# after the setup wizard creates the account.
#
# NEVER blanks and never overwrites: a value already on the row wins, so an
# operator's choice and an earlier seed's resolution both survive. Only a
# global row is touched — an account-scoped row must have both columns
# (the ai_agents CHECK constraint) and is not ours to re-own.
module CoreSeeds
  module CanonicalAgentOwner
    module_function

    # THE provider a seed should attach, given the row's model pin — the one
    # place every agent seed asks, so a hard-coded `Ai::Provider.first` or
    # `find_by(provider_type: "anthropic")` never lands on a row that cannot
    # run its pin (deploy-4 incident, 2026-09-04: the OpenAI provider written
    # onto the claude-pinned `visual-design-assistant` made it invalid on every
    # later save and aborted the hierarchy seed).
    #
    # Not a second family rule: it delegates to
    # Ai::Agents::AccountPrincipalResolver.provider_for_pin, the same rule the
    # account-clone mint uses, and offers the seed's own choice as `preferred`
    # by putting it at the head of the candidate list — so an editorial choice
    # (the concierge on OpenAI, the todo team's mixed providers) survives
    # whenever the family rule allows it, and an ACTIVE provider still wins
    # over an inactive one.
    #
    # @param pinned_model [String, nil] the row's mcp_metadata model pin
    # @param preferred [Ai::Provider, nil] the provider the seed would choose
    # @param providers [Enumerable<Ai::Provider>, nil] candidates (default: all, by priority)
    # @return [Ai::Provider, nil] nil when nothing offered can run the pin —
    #   the row is then left provider-less, which is valid on a global
    #   canonical and is the correct outcome; an invalid row is not.
    def provider_for(pinned_model:, preferred: nil, providers: nil)
      candidates = ([ preferred ].compact + (providers || ::Ai::Provider.ordered_by_priority).to_a).uniq
      chosen, compatible = ::Ai::Agents::AccountPrincipalResolver.provider_for_pin(
        pinned_model: pinned_model, providers: candidates, preferred: preferred
      )
      compatible ? chosen : nil
    end

    # @param agent [Ai::Agent, nil] the canonical just seeded
    # @param creator [User, nil] the admin user, when one exists yet
    # @param provider [Ai::Provider, nil] the provider this canonical prefers
    # @return [Ai::Agent, nil] the same row
    def backfill_owner!(agent, creator: nil, provider: nil)
      return agent unless agent.is_a?(::Ai::Agent) && agent.persisted? && agent.global?

      agent.creator = creator if creator && agent.creator_id.nil?
      if agent.ai_provider_id.nil?
        # A canonical pinned to a model its offered provider cannot run must
        # not be saved on that provider (deploy-4 incident, 2026-09-04: a
        # Claude-pinned canonical back-filled with the OpenAI provider failed
        # validation on every later save and aborted the hierarchy seed).
        # Same rule as the account-clone mint; an incompatible offer leaves
        # the global row provider-less rather than invalid.
        chosen = provider_for(
          pinned_model: agent.mcp_metadata&.dig("model_config", "model"), preferred: provider
        )
        agent.provider = chosen if chosen
      end
      agent.save! if agent.changed?
      agent
    end
  end
end
