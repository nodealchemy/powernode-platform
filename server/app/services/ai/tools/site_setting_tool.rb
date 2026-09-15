# frozen_string_literal: true

module Ai
  module Tools
    # IMP-7723206bc137 — read and write the platform's global DB-driven
    # configuration (SiteSetting) over MCP.
    #
    # THE GAP THIS CLOSES. SiteSettings are the documented home for global
    # configuration ("no hardcoded budgets/models/hostnames — make it
    # configurable"), and until now not one of them was reachable from the
    # interface the platform advertises as its control surface. The motivating
    # case was a safety invariant whose arming key could only be written by a
    # direct DB write or a Rails console on the hub — i.e. break-glass, which
    # on a hardened deployment is revoked. An invariant that can only be
    # enabled through the emergency path is not enabled.
    #
    # WHY AN ALLOWLIST AND NOT A GENERIC KEY/VALUE SETTER. Two reasons; the
    # second is the one that decided the shape.
    #
    #   1. There is nothing to redact ON. SiteSetting#setting_type is
    #      string/text/boolean/integer/json (site_setting.rb:19) — there is no
    #      "secret" or "encrypted" marker, so "serve everything except the
    #      sensitive keys" cannot be expressed. An allowlist inverts the
    #      default: a key is reachable because someone deliberately listed it,
    #      not because nothing happened to flag it.
    #   2. A tool RESULT IS NOT A PRIVATE CHANNEL. Ai::AgentToolBridgeService
    #      writes a preview of it into ai_messages.processing_metadata (durable
    #      jsonb, never re-filtered on read) and appends the full JSON as a
    #      role:"tool" message sent to the model provider on the next turn —
    #      the sink Ai::Tools::DiskImageOperatorTool documents at length. A
    #      generic getter would therefore be a standing exfiltration path for
    #      whatever an operator stores in a SiteSetting later, including
    #      credentials someone reasonably assumed were admin-only because the
    #      REST twin is.
    #
    # WHY A REGISTRY AND NOT A HARDCODED LIST. The first draft of this class
    # hardcoded the motivating key and described it by naming the extension
    # class that reads it. core-purity-check.sh blocked that, and it was right
    # to: core must not know an extension's configuration vocabulary. Keys are
    # therefore REGISTERED — core declares the ones core owns, and an extension
    # declares its own from its engine initializer. That also makes the verb
    # general, which is the actual finding: every DB-driven knob inherited this
    # gap, not just the one that surfaced it.
    #
    # Registering a key is a deliberate, reviewed act. Do not register one that
    # can hold a credential, a token or any signing material — those belong in
    # Vault, and this surface has the disclosure sink described above.
    class SiteSettingTool < BaseTool
      # MUST be a CATALOGUED permission, and must be the rung that actually
      # grants on the REST twin.
      #
      # McpPlatformToolRegistrar.enforce_permission! (:672-693) requires this
      # constant CONJUNCTIVELY for every user principal, before the tool is
      # constructed, and the same constant drives catalog visibility. So it is
      # a floor, not a hint: whatever is named here is the real gate on every
      # live MCP call, and the OR-ladder below can only ever widen within it.
      #
      # An earlier draft named "settings.manage". That string is NOT in
      # config/permissions.rb (the catalogued admin family is admin.access,
      # admin.settings.read, admin.settings.update), and
      # RolePermission#permission_must_exist_in_catalog means no role can hold
      # an uncatalogued name — so has_permission? was true only through the
      # system.admin shortcut, and the verb was reachable by system.admin
      # alone. Strictly NARROWER than the REST twin rather than wider, so it
      # failed closed, but it did not mirror the twin as this task required.
      REQUIRED_PERMISSION = "admin.access"

      # Api::V1::SiteSettingsController:5 is
      # `require_admin_access("settings.manage")`, and require_admin_access is
      # `require_any_permission("admin.access", *also_allow)`
      # (authentication.rb:320-321). EITHER admits there. admin.access is the
      # rung that actually grants today; settings.manage is kept so that if it
      # is ever catalogued, this surface admits it without a second edit —
      # it cannot widen anything while REQUIRED_PERMISSION gates the door.
      GRANTING_PERMISSIONS = %w[admin.access settings.manage].freeze

      ACTIONS = %w[site_setting_get site_setting_set site_setting_set_protected].freeze

      # IMP-70db2b60bfb3 — a write is an operator decision, so it goes through
      # Ai::AutonomyGate rather than running on the caller's say-so. An
      # ordinary key parks under WRITE_CATEGORY (no seeded policy row, so it
      # resolves to require_approval until an operator writes one). A PROTECTED
      # key — one whose change alters the control plane's authority over itself
      # — has its own human-only verb: it parks for a person to confirm in their
      # own session, and runs as that person, whatever any policy says.
      WRITE_CATEGORY = "platform.site_setting.write"
      PROTECTED_WRITE_CATEGORY = "platform.site_setting.protected_write"

      VALID_SETTING_TYPES = %w[string text boolean integer json].freeze

      class << self
        # The allowlist: key => {setting_type:, description:, protected:}. Keys
        # register themselves; nothing is reachable by default.
        def operator_configurable_keys
          @operator_configurable_keys ||= {}
        end

        # Declare a SiteSetting key as operator-configurable over MCP.
        #
        # Idempotent by key so a re-run initializer (or an eager-load in the
        # test environment) does not raise. Re-registering with a DIFFERENT
        # shape raises rather than silently taking one of them — two owners
        # disagreeing about a key's type is a defect, and the last writer
        # winning would make it depend on load order.
        #
        # `protected: true` routes every write of the key through
        # site_setting_set_protected (human-only). Protection is part of the
        # shape: an owner that registers the key unprotected conflicts with one
        # that protects it, rather than quietly relaxing it.
        def register_key(key, setting_type:, description:, protected: false)
          key = key.to_s
          unless VALID_SETTING_TYPES.include?(setting_type.to_s)
            raise ArgumentError,
                  "setting_type #{setting_type.inspect} for #{key.inspect} is not one of " \
                  "#{VALID_SETTING_TYPES.join('/')} — SiteSetting's validation would reject it"
          end

          spec = { setting_type: setting_type.to_s, description: description.to_s,
                   protected: protected == true }.freeze
          existing = operator_configurable_keys[key]
          if existing && existing != spec
            raise ArgumentError,
                  "SiteSetting key #{key.inspect} is already registered with a different " \
                  "shape (#{existing.inspect} vs #{spec.inspect}). Two owners disagree; " \
                  "resolve it rather than letting load order decide."
          end

          operator_configurable_keys[key] = spec
        end

        # True when `key` is registered protected. The REST twin
        # (Api::V1::SiteSettingsController) refuses such a key, so its only
        # write door on any surface is site_setting_set_protected.
        # Case-insensitive because SiteSetting's key uniqueness is: a case
        # variant row would make the confirmed protected write fail validation.
        def protected_key?(key)
          operator_configurable_keys.any? { |name, spec| spec[:protected] && name.casecmp?(key.to_s) }
        end
      end

      # CORE REGISTERS NO KEY OF ITS OWN, deliberately.
      #
      # A draft registered ai.autonomy.closure_driver_enabled here. Review
      # flagged it as a widening and was right: Ai::AgentToolBridgeService runs
      # tool calls as agent.creator, so registering that key would have made
      # the platform's autonomy enable-switch writable from inside an agent
      # conversation. Turning autonomy on is an operator decision, and this
      # task's direction put closure-driver semantics out of scope. It can be
      # registered later as its own reviewed act.
      #
      # The registry is therefore empty until an owner declares a key —
      # nothing is reachable by default, which is the posture this surface
      # wants.

      declare_action "site_setting_get", mutating: false
      declare_action "site_setting_set", mutating: true, audit: true,
                                         action_category: WRITE_CATEGORY,
                                         executor_class: "Ai::Executors::DeferredToolCall",
                                         gate_context: :deferred_tool_call_context,
                                         on_proceed: :deferred_tool_call_result
      declare_action "site_setting_set_protected", mutating: true, audit: true, human_only: true,
                                                   action_category: PROTECTED_WRITE_CATEGORY,
                                                   executor_class: "Ai::Executors::DeferredToolCall",
                                                   gate_context: :deferred_tool_call_context,
                                                   on_proceed: :deferred_tool_call_result

      def self.definition
        {
          name: "site_setting",
          description: "Read and write allow-listed global platform settings (SiteSetting)",
          parameters: {
            action: { type: "string", required: true, description: "One of: #{ACTIONS.join(', ')}" }
          }
        }
      end

      def self.action_definitions
        allowed = operator_configurable_keys.keys.sort.join(", ")
        ordinary = operator_configurable_keys.reject { |_, spec| spec[:protected] }.keys.sort.join(", ")
        protected_keys = operator_configurable_keys.select { |_, spec| spec[:protected] }.keys.sort.join(", ")

        {
          "site_setting_get" => {
            description: "Read one allow-listed global platform setting. Allowed keys: #{allowed}. " \
                         "A key outside that list is refused rather than served — this surface is " \
                         "persisted with the conversation and forwarded to the model provider, so it " \
                         "is not a channel for arbitrary configuration. Use the operator REST API " \
                         "(GET /api/v1/site_settings) for the full set.",
            parameters: {
              key: { type: "string", required: true, description: "Setting key. One of: #{allowed}" }
            }
          },
          "site_setting_set" => {
            description: "Request a write of one allow-listed global platform setting. Allowed keys: " \
                         "#{ordinary}. The write goes through the autonomy gate: unless an operator's " \
                         "policy proceeds the platform.site_setting.write category, it parks for " \
                         "approval and returns a pending envelope. Protected keys are refused here; " \
                         "use site_setting_set_protected. Requires admin.access or settings.manage, " \
                         "the same ladder as PUT /api/v1/site_settings/:id. Refused outright for an " \
                         "instance (node) principal or an in-process caller. Audit rows name the key " \
                         "and the actor, never the value; the value does travel with the parked request " \
                         "so the approver can see what they approve.",
            parameters: {
              key: { type: "string", required: true, description: "Setting key. One of: #{ordinary}" },
              value: { type: "string", required: true, description: "New value. Booleans accept true/false." }
            }
          },
          "site_setting_set_protected" => {
            description: "Request a write of one PROTECTED global platform setting. Protected keys: " \
                         "#{protected_keys}. Always parks for a person to confirm in their own session " \
                         "(no policy can proceed it) and runs as that person, who must hold admin.access. " \
                         "Refused outright for an instance (node) principal or an in-process caller. " \
                         "Audit rows name the key and the actor, never the value; the value travels with " \
                         "the parked request so the confirming person sees it.",
            parameters: {
              key: { type: "string", required: true, description: "Protected setting key. One of: #{protected_keys}" },
              value: { type: "string", required: true, description: "New value. Booleans accept true/false." }
            }
          }
        }
      end

      # Pre-dispatch authorization, hoisted by BaseTool so it applies to gated
      # and ungated actions alike.
      def authorization_error(params)
        # NO `return nil if internal?` either, and this one is the least
        # obvious of the three refusals. `internal: true` is the in-process
        # bypass for reconcilers and skill executors running without a user,
        # and BaseSkillExecutor#tool passes internal: internal_caller? for
        # every one of them. The moment any fleet executor nests this tool,
        # that bypass would let the hub's OWN reconciler write the key that
        # decides whether the hub may be acted upon by the plane it hosts —
        # which is INV-1 self-management performed by the control plane on
        # itself, the precise thing the key exists to prevent. There is no
        # such caller today; the refusal is here so that adding one is a
        # deliberate act rather than an accident.
        #
        # This is a narrowing of BaseTool's ladder, not a bug in it: the
        # bypass is right for verbs a reconciler needs to do its job, and
        # wrong for the switch that governs the reconciler's own authority.
        if internal?
          return error_result(
            "site_setting_* is denied to in-process internal callers. These keys govern the " \
            "control plane's own authority over itself; changing one is an operator decision, " \
            "not something a reconciler may do on its own behalf."
          )
        end

        # NO `return true if instance_authorized?` — and its absence is the
        # decision, not an omission. Sibling tools admit an mTLS node principal
        # whose tool name cleared Mcp::Principal#may_invoke?, which is right for
        # verbs a node needs to do its job. This one configures the CONTROL
        # PLANE, and at least one registered key governs whether a node may be
        # acted upon by the plane it hosts: a node able to write it could
        # disarm the guard that exists to protect the plane from itself.
        # Instance principals have already been found bypassing both permission
        # layers once on this platform; this verb does not extend them a third.
        if instance_authorized? || node_instance_principal?
          return error_result(
            "site_setting_* is denied to instance principals. These keys configure the " \
            "control plane itself, and one of them governs whether a node may be acted " \
            "upon by the plane it hosts. Use an operator (user) principal."
          )
        end

        permitted = user.respond_to?(:has_permission?) &&
                    GRANTING_PERMISSIONS.any? { |p| user.has_permission?(p) == true }
        unless permitted
          return error_result(
            "site_setting_* requires #{GRANTING_PERMISSIONS.join(' or ')} — the same ladder as " \
            "the /api/v1/site_settings operator API."
          )
        end

        write_key_error(params)
      end

      protected

      def call(params)
        # AUTHORIZE HERE TOO, not only in #authorization_error. BaseTool#execute
        # returns `call(params)` for a declared-but-UNGATED action BEFORE it
        # reaches #authorization_error, so that hook fires only on the gated
        # and human-only paths. site_setting_get is ungated, so its refusals
        # live here; for the two writes the hook has already run before the
        # park, and runs again here on the approved replay, as the principal
        # the replay was rebuilt for. Running it twice is idempotent.
        refusal = authorization_error(params)
        return refusal if refusal

        case params[:action].to_s
        when "site_setting_get" then get_setting(params)
        when "site_setting_set", "site_setting_set_protected" then set_setting(params)
        else
          error_result("Unknown action: #{params[:action].inspect} (supported: #{ACTIONS.join(', ')})")
        end
      end

      private

      # DEFENCE IN DEPTH, and honestly labelled as such rather than as a live
      # hole being closed. The streamable controller refuses an ungranted
      # restricted principal before dispatch
      # (streamable_http_controller.rb:611-614), and its one call site that
      # passes node_instance (:638) passes instance_authorized alongside it —
      # so no path today delivers node_instance WITHOUT instance_authorized.
      # An earlier comment here claimed such a principal "arrives" that way,
      # which overstated it. The check stays because it costs nothing and the
      # invariant it protects (no non-user principal writes these keys) should
      # not depend on a controller's parameter-passing staying paired.
      def node_instance_principal?
        !@node_instance.nil?
      end

      def key_spec(params)
        self.class.operator_configurable_keys[params[:key].to_s]
      end

      # Which write verb carries which key, checked BEFORE a write can park. An
      # unlisted key and a key on the wrong verb are refused here, so an
      # operator is never asked to approve a write that could only be refused
      # on replay — and an ordinary key cannot borrow the human-only verb, nor a
      # protected key slip through the policy-gated one.
      def write_key_error(params)
        action = routed_action_name(params)
        return nil unless %w[site_setting_set site_setting_set_protected].include?(action)

        spec = key_spec(params)
        return not_allowlisted_error(params) unless spec

        if spec[:protected] && action == "site_setting_set"
          return error_result(
            "#{params[:key].to_s.inspect} is a protected setting: writing it changes the control " \
            "plane's authority over itself, so it is a person's decision. Use " \
            "site_setting_set_protected, which parks for a person to confirm in their own session."
          )
        end

        if !spec[:protected] && action == "site_setting_set_protected"
          return error_result(
            "#{params[:key].to_s.inspect} is not a protected setting; use site_setting_set."
          )
        end

        nil
      end

      def not_allowlisted_error(params)
        allowed = self.class.operator_configurable_keys.keys.sort.join(", ")

        error_result(
          "#{params[:key].inspect} is not operator-configurable over MCP. This verb serves an " \
          "explicit allowlist (#{allowed}); every other setting is reachable only through the " \
          "/api/v1/site_settings operator API. The list is deliberate — a tool result is " \
          "persisted with the conversation and forwarded to the model provider, so it is not a " \
          "safe channel for arbitrary configuration."
        )
      end

      def get_setting(params)
        spec = key_spec(params)
        return not_allowlisted_error(params) unless spec

        key = params[:key].to_s
        # find_by, not SiteSetting.get: `get` returns nil both for "unset" and
        # for a boolean row holding a falsey value, and the caller has to be
        # able to tell those apart before deciding whether to write.
        row = SiteSetting.find_by(key: key)

        success_result(
          key: key,
          value: row ? SiteSetting.get(key) : nil,
          set: !row.nil?,
          setting_type: row&.setting_type || spec[:setting_type],
          description: spec[:description]
        )
      end

      def set_setting(params)
        spec = key_spec(params)
        return not_allowlisted_error(params) unless spec

        key = params[:key].to_s
        previous = SiteSetting.find_by(key: key)

        setting = SiteSetting.set(
          key,
          params[:value],
          setting_type: spec[:setting_type],
          is_public: false
        )

        record_write!(setting: setting, created: previous.nil?)

        success_result(
          key: key,
          value: SiteSetting.get(key),
          setting_type: setting.setting_type,
          created: previous.nil?
        )
      rescue ActiveRecord::RecordInvalid => e
        error_result("Validation failed: #{e.record.errors.full_messages.join(', ')}")
      end

      # Forensic context for the `audit: true` declaration on
      # site_setting_set. BaseTool writes this row through
      # Ai::SensitiveAccessAudit BEFORE #call and REFUSES the action if it does
      # not persist (base_tool.rb:474-477, sensitive_access_audit.rb:42-77) —
      # genuinely fail-closed, which a settings write deserves.
      #
      # NEVER the value. The base class's contract for this hook is that it
      # must not return the material being released, and for this tool the
      # value IS the material.
      def audit_context(action_name, params)
        {
          action: action_name,
          setting_key: params[:key].to_s,
          setting_type: self.class.operator_configurable_keys.dig(params[:key].to_s, :setting_type)
        }
      end

      # THE OUTCOME ROW, and it is NOT redundant with the one above — they
      # answer different questions, which is what an earlier draft got wrong.
      #
      # The sensitive-access row records that the action was REQUESTED: it is
      # written before #call and therefore before this tool's own
      # authorization, so a refused instance principal, an unpermissioned user
      # and an unlisted key each leave a row that looks exactly like a
      # successful write. Having dropped a hand-rolled row on the theory that
      # two ledgers meant two sources of truth, NOTHING recorded that a setting
      # had actually changed — and a forensic query for a key would surface a
      # request from a principal that was refused, inviting precisely the wrong
      # conclusion.
      #
      # So: the base row is the fail-closed REQUEST ledger, this is the
      # OUTCOME ledger, and only success reaches here.
      #
      # DIVERGENCE FROM THE REST TWIN, deliberate. Api::V1::SiteSettingsController#update
      # (:96-110) records the old and new VALUES. This does not. The allowlist
      # is open to future keys, this surface's rows are read by more people
      # than hold the write permission, and a value that is innocuous today
      # (a node id) sets the precedent for one that is not.
      def record_write!(setting:, created:)
        AuditLog.create!(
          user: user,
          account: account,
          action: "update_site_setting",
          resource_type: "SiteSetting",
          resource_id: setting.id,
          # "mcp" is NOT a valid source — AuditActions::CORE_SOURCES is
          # web/api/system/webhook/admin_panel/... and AuditLog validates
          # against it. An earlier draft used "mcp", the create! failed
          # validation, and this method's own rescue turned the missing outcome
          # row into a log line: the write succeeded and nothing recorded it.
          # The spec caught it; the rescue is why reading would not have.
          source: "api",
          metadata: {
            setting_key: setting.key,
            setting_type: setting.setting_type,
            created: created
          }
        )
      rescue StandardError => e
        # The write has already landed. Losing this row must not be reported as
        # a failed write — but it must not pass silently either, because the
        # fail-closed row above proves only that the call was ATTEMPTED.
        Rails.logger.error(
          "[SiteSettingTool] outcome audit row failed for #{setting.key}: #{e.message}"
        )
      end
    end
  end
end
