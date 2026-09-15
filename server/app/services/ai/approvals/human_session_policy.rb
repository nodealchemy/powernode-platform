# frozen_string_literal: true

module Ai
  module Approvals
    # WHICH parked requests only a person, in their own session, may decide
    # (MCP identity plan D1, guard b). Such a request is refused by name at
    # every tool door (Ai::Tools::AgentAutonomyTool) and at every REST session
    # that is not the person's own (Ai::AutonomyApprovalActions), and
    # Ai::ApprovalRequest#record_decision! refuses it from any other origin.
    #
    # In order, the first answer wins:
    #   1. a human-only action (the flag Ai::AutonomyGate writes): always, and
    #      nothing below lifts it;
    #   2. the account's own Ai::InterventionPolicy rows: an active row whose
    #      conditions carry CONDITION_KEY true or false, a row naming the
    #      category over a "*" row, then the higher priority;
    #   3. a protected environment (the plane's own flag, never a hostname);
    #   4. a parked tool call whose declaration is `destructive: true`;
    #   5. the category against the operator's site-wide list (SiteSetting
    #      SETTING_KEY, an array of File.fnmatch patterns), or, while that is
    #      not a list of strings, DEFAULT_CATEGORY_PATTERNS.
    #
    # The default lives here, not in a seed: seeds never re-run on a live
    # install, so a seeded default would never reach one.
    class HumanSessionPolicy
      SETTING_KEY = "ai_approvals_human_session_categories"
      CONDITION_KEY = "requires_human_session"

      DEFAULT_CATEGORY_PATTERNS = [
        # campaign lifecycle
        "campaign.*", "campaign_land",
        # spend
        "project.cost_control", "project.scale_horizontal",
        "system.instance_pool_create", "system.instance_pool_ceiling_raise",
        "system.runtime_docker_provision",
        # destructive, by name (a parked tool call's own declaration is read too)
        "*delete*", "*destroy*", "*terminate*", "*reap*", "*decommission*", "*revoke*"
      ].freeze

      # The refusal both REST writers of intervention-policy rows give for #mark_lifting_write?.
      MARK_WRITE_REFUSAL = "Changing whether requests need a person's own session is refused from this session: " \
                           "it needs a person acting in their own session, not an impersonation, account-switch " \
                           "or service session."

      def self.required?(request)
        new(request).required?
      end

      # Could this write to ONE intervention-policy row lift the mark #account_mark reads
      # (IMP-03134d9452d2, secreview §21 G4 option 1)? True when the row carried
      # CONDITION_KEY before the write (a change to its verb, activity, category or
      # priority, a delete, or a change of the key can each let another row's answer win),
      # or when the write sets it false. Adding the mark to a row that had none only
      # tightens, so it is not such a write. `before` and `after` are the row's conditions:
      # nil before a create, nil after a delete.
      def self.mark_lifting_write?(before:, after:)
        carries = ->(conditions) { conditions.is_a?(Hash) && conditions.stringify_keys.key?(CONDITION_KEY) }
        carries.call(before) || (after.is_a?(Hash) && after.stringify_keys[CONDITION_KEY] == false)
      end

      def initialize(request)
        @request = request
        data = request.request_data
        @data = (data.is_a?(Hash) ? data : {}).with_indifferent_access
      end

      def required?
        return true if @data[:requires_human_session] == true

        marked = account_mark
        return marked unless marked.nil?

        protected_environment? || destructive_tool_call? || category_listed?
      end

      private

      # A gate request names its category; a gateway request names its kind.
      def category
        @category ||= (@data[:action_category].presence || @data[:action_type]).to_s
      end

      def account_mark
        return nil if category.blank? || @request.account_id.blank?

        rows = ::Ai::InterventionPolicy.active
                                       .where(account_id: @request.account_id, action_category: [ category, "*" ])
                                       .select { |row| row.conditions.is_a?(Hash) && [ true, false ].include?(row.conditions[CONDITION_KEY]) }
        rows.max_by { |row| [ row.action_category == "*" ? 0 : 1, row.priority.to_i ] }&.conditions&.fetch(CONDITION_KEY)
      end

      def protected_environment?
        environment = @data[:environment]
        environment.is_a?(Hash) && environment[:is_protected] == true
      end

      # Bounded to the chokepoint's own hierarchy, as Ai::Executors::DeferredToolCall
      # bounds its replay: a name off a JSONB column is looked up, never called.
      def destructive_tool_call?
        params = @data[:params]
        return false unless params.is_a?(Hash)

        klass = params[:tool_class].to_s.safe_constantize
        return false unless klass.is_a?(Class) && klass < ::Ai::Tools::BaseTool

        klass.declared_action(params[:action].to_s)&.dig(:destructive) == true
      end

      def category_listed?
        return false if category.blank?

        patterns.any? { |pattern| File.fnmatch?(pattern, category) }
      end

      # Fail closed: a setting that is not a list of strings is ignored, never
      # read as "no categories".
      def patterns
        configured = ::SiteSetting.get(SETTING_KEY)
        return configured if configured.is_a?(Array) && configured.all?(String)

        DEFAULT_CATEGORY_PATTERNS
      end
    end
  end
end
