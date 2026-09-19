# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Single definition of how an McpServer's `capabilities` hash is
      # serialized for the worker-facing internal API (IMP-427e98cae0be).
      #
      # WHY THIS EXISTS AS ONE THING. Api::V1::Internal::McpToolExecutionsController
      # #serialize_nested_server omitted `capabilities` entirely from the
      # nested server hash it embeds in a tool-execution payload, so
      # McpSecurityService.validate_stdio_server! — called from the worker's
      # tool-execution path (Mcp::McpTransportClient#execute_stdio_tool) —
      # always saw `allow_extended_commands`/`strict_environment` as false,
      # regardless of what the server was actually configured with.
      # Api::V1::Internal::McpServersController#serialize_server already
      # returned the correct value; the two payloads must agree, so this is
      # read from ONE place rather than re-derived at each call site (the
      # same reasoning WorkerTenancy documents for the tenancy anchor).
      #
      # ALLOWLIST, NOT A PASS-THROUGH (review round 2). `capabilities` is NOT
      # secret-free: McpServer stores free-form, user-supplied `config`
      # (McpServer#config reads/writes `capabilities["config"]` — see
      # app/models/mcp_server.rb — and that config may itself hold auth) and
      # `last_error` INSIDE the same jsonb column (McpServer#last_error does
      # the same for `capabilities["last_error"]`). Returning the raw hash
      # unconditionally, as this originally did, defeated the
      # `include_config`/`include_server_config` secrecy gates at both call
      # sites — `McpServersController#index` was ALREADY leaking `config`
      # this way before this fix, since #index never opts into
      # `include_config` at all. Only the flags
      # McpSecurityService.validate_stdio_server!/#spawn_stdio actually read
      # (see app/services/mcp_security_service.rb in worker/) are returned;
      # confirmed via `command grep -rn "capabilities" worker/app` that no
      # other consumer of these two internal endpoints' payloads reads any
      # other capabilities key (config/last_error/tools/...) — the
      # discovery-scan job's `server['capabilities']['tools']` read comes
      # from a DIFFERENT endpoint (`/api/v1/internal/ai/discovery/mcp_servers`),
      # not either endpoint this concern serves.
      #
      # allow_network (IMP-a50680fd53d8) added to the allowlist: it's a
      # #spawn_stdio-time sandbox policy (whether to omit IPAddressDeny=any
      # for this server), same admin-gated trust tier as
      # allow_extended_commands, and the worker cannot apply it at all if
      # this endpoint never carries it through — exactly the bug this
      # concern was originally written to fix for allow_extended_commands.
      #
      # egress_allowlist (IMP-bf72723ef161) added the same way: it is
      # ALSO a #spawn_stdio-time sandbox policy (which IPs/hostnames the
      # worker resolves and passes to IPAddressAllow), operator-only (see
      # McpServersController::OPERATOR_ONLY_CAPABILITY_KEYS), and useless
      # to the worker unless this endpoint carries it through. Per
      # operator direction: this serializer is the ONLY path
      # egress_allowlist may ever reach the worker through — no other
      # endpoint/serializer may add it.
      module McpServerCapabilitiesSerialization
        extend ActiveSupport::Concern

        private

        def serialize_mcp_server_capabilities(server)
          (server.capabilities || {}).slice(
            'allow_extended_commands', 'strict_environment', 'allow_network', 'egress_allowlist'
          )
        end
      end
    end
  end
end
