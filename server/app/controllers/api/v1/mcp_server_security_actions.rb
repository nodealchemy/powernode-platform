# frozen_string_literal: true

module Api
  module V1
    # IMP-cdda895b07a8 — the one operator door for a stdio MCP server's sandbox
    # capabilities: allow_network, allow_extended_commands and egress_allowlist
    # (IMP-a50680fd53d8 / IMP-bf72723ef161). Until now they could be set only
    # from the Rails console: the user controller permits config: {} only, the
    # frontend sends no capabilities, and no MCP tool writes an McpServer.
    #
    # Hosted by McpServersController, which declares the route's before_actions
    # (authenticate_request, require_security_manage_permission, set_mcp_server).
    # Split out for size, not reach — nothing here is routable on its own.
    #
    # authz-ok: a controller concern, not a routable controller — it defines an
    # action reached only through McpServersController, whose before_action
    # :require_security_manage_permission gates it.
    #
    # THE MODEL IS THE RULE BOOK. This door copies none of McpServer's
    # validations (mutual exclusion of allow_network and an allowlist, forbidden
    # ranges, entry shape, the entry cap): it writes the merged capabilities and
    # lets the model refuse, so the console, this endpoint and the worker's
    # spawn-time gate cannot drift apart. What it adds is only what the model
    # cannot know: the SHAPE of the request (strict booleans, an array of
    # strings, no other key) and that the server is a stdio one.
    module McpServerSecurityActions
      extend ActiveSupport::Concern

      # The three settings this door writes, and nothing else. `strict_environment`
      # and every other capability stay console-only on purpose.
      SECURITY_CAPABILITY_KEYS = %w[allow_network allow_extended_commands egress_allowlist].freeze
      SECURITY_BOOLEAN_KEYS = %w[allow_network allow_extended_commands].freeze

      # PATCH /api/v1/mcp_servers/:id/security
      #   { security: { allow_network: bool, allow_extended_commands: bool, egress_allowlist: [string] } }
      # Partial: only the keys sent change. Audited when something changed.
      def update_security
        unless @mcp_server.connection_type == "stdio"
          return render_error("Sandbox capabilities apply to stdio MCP servers only", status: :unprocessable_content)
        end

        changes = security_changes_from_params
        return if performed?

        before = after = nil
        saved = false
        # `capabilities` is one jsonb column that the worker's reconnect path, the config
        # setter and the native-execution approval also rewrite whole, so the read-merge-write
        # runs under the row lock (with_lock reloads first) and cannot drop their changes.
        @mcp_server.with_lock do
          before = serialize_security_capabilities(@mcp_server)
          @mcp_server.capabilities = (@mcp_server.capabilities || {}).merge(changes)
          saved = @mcp_server.save
          after = serialize_security_capabilities(@mcp_server) if saved
        end

        unless saved
          return render_validation_error(@mcp_server.errors)
        end

        changed = SECURITY_CAPABILITY_KEYS.select { |key| before[key] != after[key] }
        # Audited BEFORE the response is rendered, so a failure surfaces instead of leaving a
        # committed change with no row (and never a second render).
        if changed.any?
          log_audit_event("mcp.servers.security_update", @mcp_server, severity: "high", risk_level: "high",
                                                                      metadata: { before: before, after: after, changed: changed })
        end

        render_success({
          mcp_server: serialize_mcp_server(@mcp_server),
          message: changed.empty? ? "No sandbox capability changed" : "Sandbox capabilities updated"
        })
      rescue StandardError => e
        Rails.logger.error "Failed to update MCP server security capabilities: #{e.class}: #{e.message}"
        render_error("Failed to update MCP server security capabilities", status: :internal_server_error)
      end

      private

      def require_security_manage_permission
        return if current_user.has_permission?("mcp.servers.security_manage")

        render_error("Insufficient permissions to manage MCP server security settings", status: :forbidden)
      end

      # The three settings as the operator sees them: the stored value, false /
      # [] when unset. Also what the worker is told (WORKER_CAPABILITY_KEYS).
      def serialize_security_capabilities(server)
        caps = server.capabilities.is_a?(Hash) ? server.capabilities : {}
        {
          "allow_network" => caps["allow_network"] == true,
          "allow_extended_commands" => caps["allow_extended_commands"] == true,
          "egress_allowlist" => Array(caps["egress_allowlist"])
        }
      end

      # The `security` object exactly as the client sent it. Rails' parameter
      # munging rewrites a JSON `[null]` to `[]`, which would turn a malformed
      # allowlist into a CLEAR; reading the raw JSON body keeps what was sent.
      # A non-JSON request (form-encoded) falls back to the parsed params.
      def raw_security_body
        if request.content_mime_type&.json?
          parsed = JSON.parse(request.raw_post.to_s)
          return parsed["security"] if parsed.is_a?(Hash)
        end

        raw = params[:security]
        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.stringify_keys : nil
      rescue JSON::ParserError
        nil
      end

      # Parses and shape-checks the request. Renders a 422 and returns nil for
      # anything that is not exactly the documented shape; the caller returns
      # when `performed?`. Raw JSON, not strong parameters: a scalar where an
      # array belongs must be REFUSED, not silently dropped.
      def security_changes_from_params
        body = raw_security_body
        unless body.is_a?(Hash) && body.present?
          render_error("security must be an object with at least one of #{SECURITY_CAPABILITY_KEYS.join(', ')}",
                       status: :unprocessable_content)
          return nil
        end

        unknown = body.keys - SECURITY_CAPABILITY_KEYS
        if unknown.any?
          render_error("Unsupported security setting(s): #{unknown.sort.join(', ')}. " \
                       "Only #{SECURITY_CAPABILITY_KEYS.join(', ')} can be set here",
                       status: :unprocessable_content)
          return nil
        end

        SECURITY_BOOLEAN_KEYS.each do |key|
          next unless body.key?(key)
          next if [ true, false ].include?(body[key])

          render_error("#{key} must be true or false", status: :unprocessable_content)
          return nil
        end

        if body.key?("egress_allowlist")
          list = body["egress_allowlist"]
          unless list.is_a?(Array) && list.all? { |entry| entry.is_a?(String) }
            render_error("egress_allowlist must be an array of strings", status: :unprocessable_content)
            return nil
          end
        end

        body
      end
    end
  end
end
