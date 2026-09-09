# frozen_string_literal: true

module Ai
  module Tools
    # The operator's knobs on an Ai::Environment (Environment campaign,
    # increment 4): how far one action may reach there (`max_blast_radius`),
    # whether the plane follows module publishes or is pinned
    # (`auto_promote_on_publish`), which categories always need a person
    # there (`approval_required_categories`), the default decision authority
    # and the protected flag. Every one of these was a column nothing could
    # set before this verb existed; a threshold that can only be changed by
    # editing a row is a hardcoded threshold with extra steps.
    #
    # Reads are governance reads; writes are governance management — the same
    # split GovernanceTool draws, because an environment's rules ARE the
    # governance of everything placed in it.
    class EnvironmentTool < BaseTool
      REQUIRED_PERMISSION = "ai.governance.read"

      ACTION_PERMISSIONS = {
        "environment_update" => "ai.governance.manage"
      }.freeze

      UPDATABLE = %w[
        name description max_blast_radius auto_promote_on_publish approval_required_categories
        default_decision_authority is_protected position
      ].freeze

      declare_action "environment_list", mutating: false
      declare_action "environment_update", mutating: true, audit: true

      def self.definition
        {
          name: "environment",
          description: "List and tune the account's environments (dev, ci, staging, ops, prod, ...): " \
                       "blast-radius ceiling, publish-following vs pinned, approval-required categories, " \
                       "decision authority, protection.",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "environment_list" => {
            description: "List this account's environments in ladder order (tier, then position) with every " \
                         "governance knob: tier, default_decision_authority, is_protected, is_default, " \
                         "max_blast_radius (nil = unbounded), auto_promote_on_publish (true = the plane serves a " \
                         "module's current version as soon as it is published; false = it serves only what was " \
                         "promoted into it), approval_required_categories (globs), and ladder_predecessor_slug " \
                         "(the rung a version must be on before it can be promoted here).",
            parameters: {}
          },
          "environment_update" => {
            description: "Update one environment's governance knobs. Only the keys given change. " \
                         "max_blast_radius: the most instances one gated action may touch there before it parks " \
                         "for approval (null clears the ceiling). auto_promote_on_publish: false pins the plane — " \
                         "nodes keep the version last promoted into it and a publish no longer reaches them; " \
                         "true makes it follow publishes again. approval_required_categories: globs of action " \
                         "categories that always park there. default_decision_authority: supervised | monitored | " \
                         "trusted | autonomous (supervised parks every gated operation). is_protected: destructive " \
                         "categories park there. Requires ai.governance.manage.",
            parameters: {
              environment: { type: "string", required: true, description: "Environment slug or id (account-scoped)" },
              name: { type: "string", required: false, description: "Display name" },
              description: { type: "string", required: false, description: "Free-text description" },
              max_blast_radius: { type: "integer", required: false, description: "Ceiling on instances one action may touch; null to clear" },
              auto_promote_on_publish: { type: "boolean", required: false, description: "true = follows publishes; false = pinned to promoted versions" },
              approval_required_categories: { type: "array", required: false, description: "Action-category globs that always require approval here" },
              default_decision_authority: { type: "string", required: false, enum: ::Ai::Environment::DECISION_AUTHORITIES,
                                            description: "supervised | monitored | trusted | autonomous" },
              is_protected: { type: "boolean", required: false, description: "Destructive categories park here" },
              position: { type: "integer", required: false, description: "Ordering within a tier" }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s
        unless action_permitted?(action)
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case action
        when "environment_list" then environment_list
        when "environment_update" then environment_update(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

      def environment_list
        rows = ::Ai::Environment.ladder_for(account)
        success_result(
          environments: rows.map { |e| serialize_environment(e) },
          count: rows.size,
          scope: "account",
          observed_at: Time.current.utc.iso8601
        )
      end

      def environment_update(params)
        params = params.to_h.with_indifferent_access
        environment = ::Ai::Environment.find_for_account(account.id, params[:environment].to_s)
        return error_result("Environment '#{params[:environment]}' not found in this account") unless environment

        attrs = {}
        UPDATABLE.each do |key|
          next unless params.key?(key)

          # `params[key]` may legitimately be false (auto_promote_on_publish,
          # is_protected): read by presence, never with `||`.
          attrs[key] = params[key]
        end
        return error_result("nothing to update: pass at least one of #{UPDATABLE.join(', ')}") if attrs.empty?

        if attrs.key?("approval_required_categories")
          attrs["approval_required_categories"] = Array(attrs["approval_required_categories"]).map(&:to_s)
        end

        unless environment.update(attrs)
          return error_result("update refused: #{environment.errors.full_messages.join('; ')}")
        end

        success_result(environment: serialize_environment(environment.reload), updated: attrs.keys)
      end

      def serialize_environment(e)
        {
          id: e.id,
          slug: e.slug,
          name: e.name,
          description: e.description,
          tier: e.tier,
          position: e.position,
          default_decision_authority: e.default_decision_authority,
          is_protected: e.protected?,
          is_default: e.is_default,
          max_blast_radius: e.max_blast_radius,
          auto_promote_on_publish: e.follows_publish?,
          approval_required_categories: e.approval_required_categories,
          ladder_predecessor_slug: e.ladder_predecessor&.slug,
          updated_at: e.updated_at&.utc&.iso8601
        }
      end
    end
  end
end
