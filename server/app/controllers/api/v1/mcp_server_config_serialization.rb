# frozen_string_literal: true

module Api
  module V1
    # Single definition of the account-facing allowlist for an McpServer's
    # `config` (IMP-80e613fb9c43).
    #
    # `config` is a free-form, user-suppliable jsonb hash
    # (McpServer#config reads/writes capabilities["config"] — see
    # app/models/mcp_server.rb) with no schema of its own:
    # McpServersController#mcp_server_params permits `config: {}`, so
    # nothing stopped a caller from storing arbitrary content there, and
    # #serialize_mcp_server returned it in full on every index/show/create/
    # update response — a live version of the same class of bug already
    # fixed for the worker-facing side by
    # Api::V1::Internal::McpServerCapabilitiesSerialization (see that
    # file's "ALLOWLIST, NOT A PASS-THROUGH" note, which already flagged
    # this exact endpoint as leaking `config` this way).
    #
    # THE ALLOWLIST IS THE FRONTEND'S OWN CONTRACT. McpApiService.ts reads
    # only `version`, `protocol_version`, `capabilities` (a flags object:
    # tools/resources/prompts/logging booleans), `resources_count`,
    # `prompts_count`, and `metadata` (author/url/icon) off `config` —
    # confirmed via a repo-wide read of every `.config` access in that
    # file. Nothing legitimate needs more than this, so anything else is
    # either unused or an attempt to smuggle secret-shaped content through
    # a field with no encryption/redaction of its own.
    #
    # ENFORCED ON BOTH SIDES. Input: McpServersController rejects a create/
    # update whose `config` contains a key outside this list with a 422
    # naming it, so nothing unlisted can ever be stored through this door.
    # Output: this serializer slices defensively anyway, in case a row
    # holds pre-existing or directly-seeded content from another path
    # (e.g. the worker-facing internal API, which legitimately returns the
    # raw config — see Api::V1::Internal::McpServersController#serialize_server
    # — to a completely different, worker-only trust tier).
    module McpServerConfigSerialization
      extend ActiveSupport::Concern

      # KEY -> TYPE, the single source of truth for the top-level allowlist
      # (review round 4). A key-name allowlist alone does not stop a
      # wrong-typed VALUE on an otherwise-allowed key — e.g.
      # `config: { version: { "api_key" => "..." } }` passed the old
      # name-only check, was stored, and round-tripped back out in full.
      # This map drives BOTH the 422 check (McpServersController
      # #scalar_config_type_violations) and the serializer below, so there
      # is one contract instead of two ad-hoc checks that could drift.
      # capabilities/metadata are typed Hash here for that reason (their
      # top-level shape is validated from this map too), but their INSIDE
      # content has its own dedicated sub-allowlist below — a Hash-shaped
      # value is necessary but not sufficient for those two keys.
      CONFIG_KEY_TYPES = {
        "version" => String,
        "protocol_version" => String,
        "capabilities" => Hash,
        "resources_count" => Integer,
        "prompts_count" => Integer,
        "metadata" => Hash
      }.freeze

      ALLOWED_CONFIG_KEYS = CONFIG_KEY_TYPES.keys.freeze

      # SECOND-LEVEL ALLOWLIST (IMP-80e613fb9c43 review round 2). A
      # top-level key allowlist alone does not stop content smuggled
      # *inside* an allowed nested hash — e.g. config.metadata.author
      # holding an object instead of the plain string every real caller
      # sends. Each nested key here also constrains the VALUE'S type, not
      # just its name.
      ALLOWED_CAPABILITIES_KEYS = %w[tools resources prompts logging].freeze
      ALLOWED_METADATA_KEYS = %w[author url icon].freeze

      private

      def serialize_mcp_server_config(server)
        config = (server.config || {}).slice(*ALLOWED_CONFIG_KEYS)

        CONFIG_KEY_TYPES.each do |key, type|
          next if type == Hash # capabilities/metadata are sanitized below instead
          next unless config.key?(key)

          config.delete(key) unless config[key].is_a?(type)
        end

        config["capabilities"] = sanitize_config_capabilities(config["capabilities"])
        config["metadata"] = sanitize_config_metadata(config["metadata"])
        config.compact
      end

      def sanitize_config_capabilities(value)
        return nil unless value.is_a?(Hash)

        value.slice(*ALLOWED_CAPABILITIES_KEYS).select { |_, v| v == true || v == false }
      end

      def sanitize_config_metadata(value)
        return nil unless value.is_a?(Hash)

        value.slice(*ALLOWED_METADATA_KEYS).select { |_, v| v.is_a?(String) }
      end
    end
  end
end
