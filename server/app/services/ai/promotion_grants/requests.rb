# frozen_string_literal: true

module Ai
  module PromotionGrants
    # An agent ASKS for a promotion grant (Ai::PromotionGrantRequest): the
    # request parks as a human-only approval card, decided by a person in their
    # own session, and only that decision issues anything.
    #
    #   request!  -> ai.promotion_grant.requested
    #
    # Everything that says WHO and WHAT it is bound to comes from the caller's
    # own state, passed in by the tool: the agent (it asks for itself), the
    # driving user, the door, and the binding target (the MCP session the call
    # arrived on, or the run making it). Params name only the terms.
    module Requests
      class Refused < StandardError; end

      BINDS = {
        "none" => nil,
        "session" => ::Ai::PromotionGrant::BINDING_MCP_SESSION,
        "run" => ::Ai::PromotionGrant::BINDING_AGENT_EXECUTION
      }.freeze
      CHAIN_NAME = "Promotion Grant Requests"
      CHAIN_TIMEOUT_HOURS = 4

      module_function

      # @param agent [Ai::Agent] the requesting agent: the tool's own
      # @param mcp_session [McpSession, nil] the call's owner-resolved session
      # @param agent_execution [Ai::AgentExecution, nil] the run making the call
      # @param terms [Hash] environment (id or slug), action_category,
      #   module_ids, max_uses, expires_in_hours, reason, granter_driven_only, bind
      # @return [Array(Ai::PromotionGrantRequest, Boolean)] the request and
      #   whether it is an already-pending one (deduped)
      def request!(account:, agent:, terms:, user: nil, call_origin: nil, mcp_session: nil, agent_execution: nil)
        raise Refused, "Only an agent may request a promotion grant, for itself" if agent.nil?
        # Canonical/shadow rule: only an account row runs, so only one asks.
        if agent.account_id.nil?
          raise Refused, "A global canonical agent is a read-only template and cannot request a grant; " \
                         "its account row (the shadow that runs) asks for itself"
        end
        raise Refused, "The agent is not in this account" unless agent.account_id == account.id

        terms = terms.to_h.with_indifferent_access
        bind = terms[:bind].to_s
        raise Refused, "bind must be one of: #{BINDS.keys.join(', ')}" unless BINDS.key?(bind)

        binding_kind = BINDS[bind]
        binding_id = resolve_binding_id(binding_kind, account: account, agent: agent, mcp_session: mcp_session,
                                                      agent_execution: agent_execution)
        environment = resolve_environment(account, terms[:environment])
        category = terms[:action_category].presence || ::Ai::PromotionGrant::CATEGORIES.first
        unless ::Ai::PromotionGrants::Grantable.grantable?(category)
          raise Refused, "#{category} is not a category a promotion grant may name"
        end
        if ::Ai::PromotionGrants::Catalog.required_permission(category).nil?
          raise Refused, "No installed extension declares #{category} as grantable, so no grant for it can be issued"
        end

        module_ids = Array(terms[:module_ids]).map(&:to_s)
        unknown = ::Ai::PromotionGrants::Catalog.unknown_subject_ids(account: account, action_category: category,
                                                                     ids: module_ids)
        raise Refused, "module_ids name no module in this account: #{unknown.join(', ')}" if unknown.any?

        ::Ai::PromotionGrantRequest.transaction do
          # Serialises this agent's requests, so the cap and the dedupe below
          # cannot both be passed by two racing calls.
          agent.lock!
          pending = ::Ai::PromotionGrantRequest.pending.where(ai_agent_id: agent.id)
          existing = pending.find_by(environment_id: environment.id, action_category: category)
          next [ existing, true ] if existing

          if pending.count >= ::Ai::PromotionGrantRequest::MAX_PENDING_PER_AGENT
            raise Refused, "This agent already has #{::Ai::PromotionGrantRequest::MAX_PENDING_PER_AGENT} pending " \
                           "promotion grant requests; wait for a decision before asking again"
          end

          grant_request = ::Ai::PromotionGrantRequest.create!(
            account: account, agent: agent, environment: environment, requested_by: user,
            action_category: category, module_ids: module_ids, max_uses: terms[:max_uses].presence,
            lifetime_seconds: lifetime_seconds(terms[:expires_in_hours]), reason: terms[:reason],
            granter_driven_only: ActiveModel::Type::Boolean.new.cast(terms[:granter_driven_only]) || false,
            binding_kind: binding_kind, binding_id: binding_id, call_origin: call_origin
          )
          approval = park!(grant_request, user: user, call_origin: call_origin)
          grant_request.update!(approval_request: approval)
          audit_requested!(grant_request, user: user)
          [ grant_request, false ]
        end
      rescue ActiveRecord::RecordInvalid => e
        raise Refused, e.record.errors.full_messages.join(", ")
      end

      # The card a person decides. Human-only EXPLICITLY: the category is on no
      # default human-session list, so without the mark an operator's chain
      # set to approve on timeout would approve it.
      def park!(grant_request, user:, call_origin:)
        chain = ::Ai::ApprovalChain.find_or_strengthen!(
          account: grant_request.account, name: CHAIN_NAME, step_name: "Operator Approval",
          approvers: [ { "type" => "permission", "value" => ::Ai::PromotionGrantRequest::MANAGE_PERMISSION } ],
          required_approvals: 1,
          defaults: {
            trigger_type: "autonomy_action", status: "active", is_sequential: true,
            timeout_hours: CHAIN_TIMEOUT_HOURS, timeout_action: "reject"
          }
        )
        chain.create_request!(
          source_type: grant_request.class.name,
          source_id: grant_request.id,
          description: "#{grant_request.agent.name} asks for a #{grant_request.action_category} grant into " \
                       "#{grant_request.environment.slug} (#{grant_request.binding_description})",
          request_data: card_data(grant_request).merge(
            "requires_human_session" => true,
            "call_origin" => call_origin
          ).compact,
          requested_by: user
        )
      end

      # The frozen terms and the binding, as the card and the API render them.
      def card_data(grant_request)
        environment = grant_request.environment
        {
          "action_category" => ::Ai::PromotionGrantRequest::APPROVAL_CATEGORY,
          "grant_category" => grant_request.action_category,
          "agent_id" => grant_request.ai_agent_id,
          "agent_name" => grant_request.agent.name,
          "promotion_grant_request_id" => grant_request.id,
          "environment" => { "id" => environment.id, "slug" => environment.slug,
                             "is_protected" => environment.protected? },
          "terms" => grant_request.terms.merge(
            "expires_in_hours" => (grant_request.lifetime_seconds / 3600.0).round(2),
            "environment_slug" => environment.slug
          ),
          "binding" => {
            "kind" => grant_request.binding_kind, "id" => grant_request.binding_id,
            "description" => grant_request.binding_description
          }
        }
      end

      def resolve_binding_id(kind, account:, agent:, mcp_session:, agent_execution:)
        case kind
        when nil then nil
        when ::Ai::PromotionGrant::BINDING_MCP_SESSION
          unless mcp_session && mcp_session.account_id == account.id && mcp_session.live? &&
                 mcp_session.ai_agent_id == agent.id
            raise Refused, "bind: \"session\" needs this call to arrive on your own live MCP session"
          end
          mcp_session.id
        when ::Ai::PromotionGrant::BINDING_AGENT_EXECUTION
          unless agent_execution && agent_execution.account_id == account.id && agent_execution.running? &&
                 agent_execution.ai_agent_id == agent.id
            raise Refused, "bind: \"run\" needs this call to come from your own running execution"
          end
          agent_execution.id
        end
      end

      def resolve_environment(account, ref)
        raise Refused, "environment is required (an environment id or slug)" if ref.blank?

        scope = ::Ai::Environment.where(account_id: account.id)
        by_id = ref.to_s.match?(::Ai::PromotionGrant::UUID_FORMAT) ? scope.find_by(id: ref.to_s) : nil
        by_id || scope.find_by(slug: ref.to_s) || raise(Refused, "unknown environment #{ref}")
      end

      def lifetime_seconds(hours)
        value = Float(hours.to_s, exception: false)
        raise Refused, "expires_in_hours must be a positive, finite number of hours" unless value&.finite? && value.positive?

        (value * 3600).round
      end

      def audit_requested!(grant_request, user:)
        details = card_data(grant_request).merge("approval_request_id" => grant_request.approval_request_id,
                                                 "call_origin" => grant_request.call_origin)
        ::AuditLog.create!(
          account_id: grant_request.account_id, user: user, action: Ledger::REQUESTED, source: "system",
          resource_type: grant_request.class.name, resource_id: grant_request.id,
          severity: "medium", risk_level: "medium", new_values: details, metadata: details
        )
      end
    end
  end
end
