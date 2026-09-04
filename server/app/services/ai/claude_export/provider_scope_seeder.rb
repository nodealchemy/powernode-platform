# frozen_string_literal: true

module Ai
  module ClaudeExport
    # The synthetic `claude-code` Ai::Provider scope: one INACTIVE,
    # credential-less, non-routable row per account that
    # Ai::ClaudeExport::ExecutionRecorder records a Claude Code run under when
    # the account holds no credentialed Anthropic provider. It is a bookkeeping
    # scope for model statistics, never a routing target
    # (Ai::Provider.platform_routable excludes it by metadata.execution_source).
    #
    # WHO MINTS IT (IMP-e8513b30152d): this seam only — the baseline seed
    # (db/seeds/ai_claude_code_provider_seed.rb, every account at seed time),
    # Setup::FirstAdminService (a wizard install's FIRST account, whose seed
    # step is an extension seam that no-ops in core mode), Accounts::
    # ProvisionService (a tenant created after first boot, since seeds never
    # re-run), and `rake db:seed:claude_code_provider_scopes` (the ESTABLISHED
    # install, where db:seed is first-boot only — see the task's header).
    # The report path (platform.record_agent_execution,
    # reachable by any ai.agents.execute holder — including the SubagentStop
    # hook's instance principal) resolves the row and refuses when it is
    # absent; that grant must not be able to create a provider row.
    #
    # IDENTITY: ai_providers has no source_key column; the row is keyed by the
    # per-account UNIQUE `provider_identifier` (index on account_id +
    # provider_identifier) carrying SOURCE_KEY, mirrored into metadata for
    # readers that only see the jsonb bag. Lookup stays on the UNIQUE slug so a
    # row minted by the pre-seed on-demand path is ADOPTED (source key
    # backfilled) rather than duplicated.
    #
    # `supported_models` stays empty on purpose: Ai::AgentModelSelector
    # enumerates candidates from it, and an inactive provider is already
    # outside its candidate set; platform_routable closes the fallback arm.
    class ProviderScopeSeeder
      SLUG = "claude-code"
      NAME = "Claude Code (local sessions)"
      SOURCE_KEY = "core:ai_claude_code_provider_seed:claude-code"
      # RFC 2606 reserved TLD: this provider row never serves a request; the
      # endpoint exists only because Ai::Provider validates one.
      ENDPOINT = "https://claude-code.invalid"
      # Anthropic is the only provider family Claude Code runs.
      PROVIDER_TYPE = "anthropic"
      SEED_FILE = "db/seeds/ai_claude_code_provider_seed.rb"
      # The absence-only backfill an ESTABLISHED install runs (db:seed is
      # first-boot only). Defined in lib/tasks/seed.rake.
      REMEDY_TASK = "rails db:seed:claude_code_provider_scopes"

      # The seeded scope for an account, or nil. Never creates.
      # @param account [Account]
      # @return [Ai::Provider, nil]
      def self.find_for(account)
        account.ai_providers.find_by(slug: SLUG)
      end

      # Create the scope for one account, or adopt an existing row under the
      # same slug (backfilling its source key). Idempotent, and safe to call
      # inside a caller's open transaction: Accounts::ProvisionService does,
      # and a nested save would otherwise JOIN that transaction, so losing the
      # unique-index race would poison it and the rescue's re-read would raise
      # "current transaction is aborted" instead of adopting. `requires_new`
      # puts the insert in its own SAVEPOINT, which is what the rescue unwinds.
      # @param account [Account]
      # @return [Ai::Provider]
      def self.ensure_for!(account)
        existing = find_for(account)
        return adopt!(existing) if existing

        create_scope!(account)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Only a LOST UNIQUENESS RACE is recoverable (the model validates the
        # slug, so a concurrent insert surfaces either way). If no row is
        # actually there the create failed for some other reason — re-raise it
        # rather than trading it for a confusing RecordNotFound.
        existing = account.ai_providers.find_by(slug: SLUG)
        raise unless existing

        adopt!(existing)
      end

      def self.create_scope!(account)
        ::Ai::Provider.transaction(requires_new: true) do
          account.ai_providers.create!(
            name: NAME,
            slug: SLUG,
            provider_identifier: SOURCE_KEY,
            provider_type: PROVIDER_TYPE,
            description: "Synthetic scope for Claude Code runs of platform agents reported through " \
                         "platform.record_agent_execution. Not a platform routing candidate.",
            api_base_url: ENDPOINT,
            api_endpoint: ENDPOINT,
            capabilities: %w[text_generation chat],
            supported_models: [],
            configuration_schema: { "type" => "object", "properties" => {} },
            requires_auth: false,
            is_active: false,
            metadata: metadata_for({})
          )
        end
      end
      private_class_method :create_scope!

      # Every account. Returns the number of scopes created or adopted.
      # @return [Integer]
      def self.ensure_all!
        count = 0
        Account.find_each do |account|
          ensure_for!(account)
          count += 1
        end
        count
      end

      def self.adopt!(provider)
        attrs = {}
        attrs[:provider_identifier] = SOURCE_KEY unless provider.provider_identifier == SOURCE_KEY
        merged = metadata_for(provider.metadata || {})
        attrs[:metadata] = merged unless merged == provider.metadata
        provider.update!(attrs) if attrs.any?
        provider
      end
      private_class_method :adopt!

      def self.metadata_for(metadata)
        metadata.merge(
          "execution_source" => ::Ai::AgentExecution::CLAUDE_CODE_SOURCE,
          "synthetic" => true,
          "source_key" => SOURCE_KEY
        )
      end
      private_class_method :metadata_for
    end
  end
end
