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
      # An earlier draft named "settings.manage" as this floor. It is a real,
      # catalogued permission (config/permissions.rb, granted to the owner and
      # admin roles), but it is not the floor: the registrar enforces THIS
      # constant conjunctively, so a settings.manage holder without admin.access
      # is refused at the MCP door and cannot complete a protected approval.
      REQUIRED_PERMISSION = "admin.access"

      # Api::V1::SiteSettingsController:5 is
      # `require_admin_access("settings.manage")`, and require_admin_access is
      # `require_any_permission("admin.access", *also_allow)`
      # (authentication.rb:320-321). EITHER admits there. admin.access is the
      # rung the MCP door requires; settings.manage (catalogued, held by every
      # tenant Account Owner) widens only the reads on this surface that do not
      # pass through that door, such as the approval card's current value.
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
        # `machine_parkable: true` lets an INSTANCE principal REQUEST a write of a
        # protected key (park it for a person to decide). It is an explicit,
        # per-key opt-in: a protected key is person-initiated only unless its
        # owner names it here, and it changes who may ASK, never who may decide
        # or run. It is meaningful only with `protected: true`.
        #
        # `protected: true` routes every write of the key through
        # site_setting_set_protected (human-only). Protection is part of the
        # shape: an owner that registers the key unprotected conflicts with one
        # that protects it, rather than quietly relaxing it.
        #
        # `ordering:` (IMP-1765f6f09458) is how restrictive a value is, declared
        # by the key's registrar for a machine-parkable key: a callable
        # `(requested, current) -> true` answering "is the requested value at
        # least as restrictive as the current one". Both values arrive cast to
        # the key's setting_type (SiteSetting.cast_stored); `current` is nil
        # when the setting is unset, and what unset MEANS is the registrar's to
        # decide (for a guard whose unset state refuses everything, nothing
        # tightens it). A machine park is accepted only when the ordering
        # answers exactly true; a machine-parkable key with NO ordering is not
        # machine-parkable for a changed value at all. It binds MACHINES only: a
        # person parks whatever the value check admits. Core declares no key's
        # ordering — the tool does not know what "tighter" means for a key.
        #
        # Kept beside the spec, not in it: the spec is frozen data compared for
        # equality on re-registration, and two evaluations of one initializer
        # produce two Procs, so an ordering inside it would make every reload
        # raise as a "different shape".
        def register_key(key, setting_type:, description:, protected: false, machine_parkable: false, ordering: nil)
          key = key.to_s
          unless VALID_SETTING_TYPES.include?(setting_type.to_s)
            raise ArgumentError,
                  "setting_type #{setting_type.inspect} for #{key.inspect} is not one of " \
                  "#{VALID_SETTING_TYPES.join('/')} — SiteSetting's validation would reject it"
          end
          if ordering && machine_parkable != true
            raise ArgumentError,
                  "an ordering for #{key.inspect} means nothing without machine_parkable: true — " \
                  "it binds what a machine may request, and this key admits no machine request"
          end
          if ordering && !ordering.respond_to?(:call)
            raise ArgumentError, "the ordering for #{key.inspect} must be callable as (requested, current)"
          end

          spec = { setting_type: setting_type.to_s, description: description.to_s,
                   protected: protected == true, machine_parkable: machine_parkable == true }.freeze
          existing = operator_configurable_keys[key]
          if existing && existing != spec
            raise ArgumentError,
                  "SiteSetting key #{key.inspect} is already registered with a different " \
                  "shape (#{existing.inspect} vs #{spec.inspect}). Two owners disagree; " \
                  "resolve it rather than letting load order decide."
          end
          # The ordering is part of the conflict rule too: a later call may
          # neither replace it (a looser one would quietly widen what a machine
          # may request), drop it, nor add one to a key registered without (that
          # widens it from "no changed value" to "some"). The SAME ordering — the
          # same code location, as a re-run initializer produces — is idempotent.
          if existing && !same_ordering?(machine_park_orderings[key], ordering)
            raise ArgumentError,
                  "SiteSetting key #{key.inspect} is already registered with a different machine-park " \
                  "ordering (#{describe_ordering(machine_park_orderings[key])} vs #{describe_ordering(ordering)}). " \
                  "Two owners disagree; resolve it rather than letting load order decide."
          end

          operator_configurable_keys[key] = spec
          machine_park_orderings[key] = ordering if ordering
        end

        def same_ordering?(existing, ordering)
          return existing.nil? if ordering.nil?
          return false if existing.nil?

          existing == ordering ||
            (existing.respond_to?(:source_location) && ordering.respond_to?(:source_location) &&
             !existing.source_location.nil? && existing.source_location == ordering.source_location)
        end
        private :same_ordering?

        def describe_ordering(ordering)
          return "none" if ordering.nil?

          location = ordering.respond_to?(:source_location) ? ordering.source_location : nil
          location ? location.join(":") : ordering.class.name
        end
        private :describe_ordering

        # key => the ordering its registrar declared (see #register_key). A
        # machine-parkable key absent here refuses every machine park that
        # changes the value.
        def machine_park_orderings
          @machine_park_orderings ||= {}
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

      # NOTHING IS REGISTERED HERE. Owners register their own keys, core
      # included: config/initializers/human_session_setting_keys.rb declares the
      # human-session category list PROTECTED (IMP-d0403597f455), which NARROWS
      # that key — registering it is what lets every door tell it from an
      # ordinary row and refuse it.
      #
      # Registering an UNPROTECTED key is the widening to weigh. A draft
      # registered ai.autonomy.closure_driver_enabled here and review was right
      # to flag it: Ai::AgentToolBridgeService runs tool calls as agent.creator,
      # so that would have made the platform's autonomy enable-switch writable
      # from inside an agent conversation. A protected key carries no such
      # WRITE reach — its only write door is the human-only verb. Reads used to
      # be a separate, unguarded question (IMP-872269ef50a5): `protected` did
      # not answer it, and site_setting_get served every registered key's
      # value, protected ones included, to any admin.access holder. #read_key_error
      # below closes that: a protected key's value is never served over MCP —
      # read it through the operator REST API instead.
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
        ordinary = operator_configurable_keys.reject { |_, spec| spec[:protected] }.keys.sort.join(", ")
        protected_keys = operator_configurable_keys.select { |_, spec| spec[:protected] }.keys.sort.join(", ")

        {
          "site_setting_get" => {
            description: "Read one allow-listed global platform setting. Allowed keys: #{ordinary}. " \
                         "A key outside that list is refused rather than served — this surface is " \
                         "persisted with the conversation and forwarded to the model provider, so it " \
                         "is not a channel for arbitrary configuration. Protected keys (#{protected_keys}) " \
                         "are refused here too, even to an admin.access holder — their value is never " \
                         "served over MCP. Use the operator REST API (GET /api/v1/site_settings) to read " \
                         "a protected key's current value, or the full set.",
            parameters: {
              key: { type: "string", required: true, description: "Setting key. One of: #{ordinary}" }
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
                         "An instance (node) principal may REQUEST it only when its grant names this " \
                         "tool exactly (a glob does not qualify) and the key is registered " \
                         "machine-parkable, and only to TIGHTEN it: the requested value must be at " \
                         "least as restrictive as the current one under the ordering the key's " \
                         "owner declared (a loosening, or a key with no declared ordering, is refused " \
                         "for a changed value). It can never decide or run it, a person does, in their " \
                         "own session. Refused outright for an in-process caller. " \
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

        read_key_error(params) || write_key_error(params)
      end

      # What a call meets before it PARKS (BaseTool#park_authorization_error;
      # only the human-only verb parks). It differs from #authorization_error in
      # ONE respect: an INSTANCE principal whose grant cleared this exact tool
      # name is admitted, so an operator's Claude Code session can REQUEST a
      # protected change. Parking runs nothing and writes nothing: the request
      # waits for a person, who decides it in their own REST session, and the
      # write then runs AS that person.
      #
      # Everything else is held. An in-process internal caller is refused as
      # ever. The key must be a registered PROTECTED key and the value must pass
      # its check, so no operator is asked to approve a change that could only
      # fail on replay. And #authorization_error is untouched: it still refuses
      # every instance principal, and it is what #call re-runs on the replay, so
      # an instance can park a request and can never reach the write, not by
      # replaying it and not by approving it (no tool door is a person's consent).
      #
      # NO `instance_authorized?` was added to #authorization_error, and none may
      # be: that would let an instance run the write, not only ask for it.
      def park_authorization_error(params)
        return authorization_error(params) unless instance_authorized? || node_instance_principal?
        return authorization_error(params) unless routed_action_name(params) == "site_setting_set_protected"

        code, refusal = park_refusal(params)
        audit_park_refusal(params, code) if refusal
        refusal
      end

      def park_dedupe_key(params)
        key = params[:key].to_s
        key.present? ? "site_setting:#{key.downcase}" : nil
      end

      # The approval card for a parked protected-setting request: the exact tool,
      # the key and the NEW value (both from the request's redacted request_data,
      # passed in by the caller), and the CURRENT value, read now, and only for a
      # viewer who could read it on the operator REST API (GET /api/v1/site_settings).
      # nil for anything else. Never rendered into a free-text description.
      def self.approval_change_card(action:, tool_params:, viewer:)
        return nil unless action.to_s == "site_setting_set_protected" && tool_params.is_a?(Hash)

        key = tool_params.with_indifferent_access[:key].to_s
        return nil unless operator_configurable_keys.dig(key, :protected)

        card = { tool: "site_setting", action: action.to_s, key: key,
                 new_value: tool_params.with_indifferent_access[:value] }
        readable = viewer.respond_to?(:has_permission?) &&
                   GRANTING_PERMISSIONS.any? { |permission| viewer.has_permission?(permission) == true }
        return card unless readable

        row = SiteSetting.find_by(key: key)
        card = card.merge(current_value: row&.value, current_value_set: !row.nil?)
        present_card_values(card, key, viewer)
      end

      # A presenter's rendering of the values, added NEXT TO the raw ones (they
      # stay in the card: the approver must see exactly what gets written). Only
      # for a holder of REQUIRED_PERMISSION (admin.access), NOT the wider
      # GRANTING_PERMISSIONS ladder above: a presentation can carry more than the
      # raw value does (names and owning accounts behind bare ids), settings.manage
      # is held by every tenant Account Owner, and admin.access is the only
      # permission that can complete this approval, so narrowing loses nothing.
      # Absent when the key has no presenter or the presenter failed
      # (SiteSetting.present_value never raises).
      def self.present_card_values(card, key, viewer)
        return card unless viewer.has_permission?(REQUIRED_PERMISSION) == true

        presented = { presented_new_value: SiteSetting.present_value(key, card[:new_value], viewer: viewer) }
        if card[:current_value_set]
          presented[:presented_current_value] = SiteSetting.present_value(key, card[:current_value], viewer: viewer)
        end
        card.merge(presented.compact)
      end
      private_class_method :present_card_values

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

      # Why an instance may not PARK this call, as [reason_code, envelope], or
      # nil when it may. The grant is re-asked here against the name the first hop
      # was gated on, exactly as the replay re-asks it
      # (Ai::Executors::DeferredToolCall), and the value is checked against the
      # key's own registered check. The code, never the envelope, is audited: an
      # envelope can echo a value.
      def park_refusal(params)
        if internal?
          return [ "internal_caller", error_result(
            "site_setting_* is denied to in-process internal callers. These keys govern the " \
            "control plane's own authority over itself; changing one is an operator decision, " \
            "not something a reconciler may do on its own behalf."
          ) ]
        end
        unless instance_authorized?
          return [ "not_instance", park_denied("it is not an authenticated instance principal") ]
        end
        if node_instance.nil?
          return [ "no_node_instance", park_denied("it carries no node instance to attribute the request to") ]
        end
        unless park_grant_cleared?(params)
          return [ "grant_not_cleared", park_denied("its grant does not name site_setting_set_protected") ]
        end

        key_refusal = write_key_error(params)
        return [ "key_refused", key_refusal ] if key_refusal
        unless key_spec(params)[:machine_parkable]
          return [ "key_not_machine_parkable", error_result(
            "#{params[:key].to_s.inspect} is a protected setting that only a person may initiate a change to; " \
            "an instance principal may request only the keys registered machine_parkable."
          ) ]
        end

        value_refusal = value_error(params)
        value_refusal ? [ "value_refused", value_refusal ] : nil
      end

      # The tightening check runs HERE, inside Ai::Approvals::MachinePark's guard
      # (BaseTool#guarded_park_refusal), not in #park_refusal above: its answer
      # depends on the current value, which an instance may not read, so asking
      # it must cost what a park costs. Under the guard it is deduped against
      # this principal's pending request for the key (which answers nothing
      # about the value), it runs only inside the window, and its audit row —
      # written on EVERY refusal, never collapsed — spends that window.
      def guarded_park_refusal(params)
        code, refusal = tightening_refusal(params)
        audit_park_refusal(params, code, collapse: false) if refusal
        refusal
      end

      # A machine may only TIGHTEN (IMP-1765f6f09458). The requested value and
      # the current one, both cast to the key's registered type, go to the
      # ordering the key's registrar declared; anything but exactly `true` refuses.
      # [reason_code, envelope] or nil. Fails closed on every edge: no ordering
      # declared (a changed value is refused; the unchanged value is not a
      # change), a stored row of another type, the ordering raising. The envelope
      # names the key and never a value: the instance cannot read a protected
      # key, and the current value must not come back as an error message.
      def tightening_refusal(params)
        key = params[:key].to_s
        spec = key_spec(params)
        row = SiteSetting.find_by(key: key)
        if row && row.setting_type != spec[:setting_type]
          return [ "current_type_mismatch", error_result(
            "#{key.inspect} is stored as #{row.setting_type} but registered as #{spec[:setting_type]}; " \
            "an instance principal cannot request a change to it until an operator resolves that."
          ) ]
        end

        requested = SiteSetting.cast_stored(stored_form(spec, params[:value]), spec[:setting_type])
        current = row ? SiteSetting.cast_stored(row.value, spec[:setting_type]) : nil

        ordering = self.class.machine_park_orderings[key]
        if ordering.nil?
          return nil if row && requested == current

          return [ "ordering_undeclared", error_result(
            "#{key.inspect} declares no ordering, so an instance principal may not request a changed " \
            "value for it: only a person may. Its owner can declare one (register_key ordering:) if a " \
            "machine should be able to tighten it."
          ) ]
        end

        answer =
          begin
            ordering.call(requested, current)
          rescue StandardError => e
            Rails.logger.error("[SiteSettingTool] ordering for #{key} raised: #{e.class}")
            return [ "ordering_failed", tightening_denied(key) ]
          end

        answer == true ? nil : [ "not_tightening", tightening_denied(key) ]
      end

      def tightening_denied(key)
        error_result(
          "#{key.inspect} is a protected setting an instance principal may only tighten: the requested " \
          "value is not at least as restrictive as the current one. A person may request a loosening, " \
          "in their own session."
        )
      end

      # The value as SiteSetting.set will store it (the form the value check and
      # the ordering compare).
      def stored_form(spec, value)
        spec[:setting_type] == "json" && !value.is_a?(String) ? value.to_json : value.to_s
      end

      # THE WRITE re-asks the ordering for a MACHINE-requested request
      # (IMP-1765f6f09458): the park checked it against the value current THEN,
      # and the decision may come hours later. The digest the approve door
      # verifies binds the person to the value they saw, but the workflow service
      # is reachable without that door, and "a machine may only tighten" has to
      # hold at the write on every door. Only a machine's request: a person's own
      # loosening is theirs to make. nil when nothing objects.
      def machine_request_tightening_refusal(params)
        return nil unless human_confirmed_replay?

        request = @replaying_operation.try(:approval_request)
        return nil unless request.respond_to?(:machine_requested?) && request.machine_requested?

        _code, refusal = tightening_refusal(params)
        refusal
      end

      def park_denied(reason)
        error_result(
          "site_setting_set_protected cannot be requested by this instance principal: #{reason}. " \
          "An operator grants the tool by exact name (platform.site_setting_set_protected); a glob does not qualify."
        )
      end

      # The grant must NAME the tool: the literal name is among the principal's
      # granted patterns. A glob (`platform.*`, `platform.site_setting*`) that
      # merely covers it does not qualify, so a broad grant an instance already
      # holds for other work never becomes a licence to ask for protected changes.
      # may_invoke? is asked as well, so the destroy-shaped deny overlay still holds.
      def park_grant_cleared?(params)
        principal = ::Mcp::Principal.for_instance_cn(node_instance.id)
        return false if principal.nil? || principal.account&.id != account&.id

        name = "platform.#{granted_tool_name_for(routed_action_name(params))}"
        principal.granted_tool_patterns.include?(name) && principal.may_invoke?(name)
      end

      # The key's registered value check, and the presence rule SiteSetting
      # applies, run against the value as it will be stored. Not `valid?` on a
      # built row: that would also run the uniqueness check against the row this
      # write is meant to replace.
      def value_error(params)
        key = params[:key].to_s
        spec = key_spec(params)
        stored = stored_form(spec, params[:value])

        if stored.blank? && spec[:setting_type] != "boolean" && !SiteSetting::BLANK_ALLOWED_KEYS.include?(key)
          return error_result("#{key.inspect} needs a value.")
        end

        reason = SiteSetting.value_checks[key]&.call(stored)
        reason.present? ? error_result("#{key.inspect} refuses that value: #{reason}") : nil
      end

      # A refused park is recorded, once per (principal, reason) a minute so a
      # looping session cannot bloat the log (failing open when the cache is
      # unavailable: Ai::Approvals::MachinePark.audit_once?). Names the principal, the reason
      # code and the key ONLY when it is a registered one, never a value or
      # caller-supplied text; a lost row costs visibility only, so it is logged,
      # not raised.
      #
      # `collapse: false` for a refusal that is METERED (the tightening check,
      # #guarded_park_refusal): every one is written, and the row, naming the
      # action category and the node instance, is what Ai::Approvals::MachinePark
      # counts against the principal's window.
      def audit_park_refusal(params, code, collapse: true)
        if collapse
          return unless ::Ai::Approvals::MachinePark.audit_once?("site_setting:park_refusal_audit:#{node_instance&.id}:#{code}")
        end

        registered = key_spec(params) ? params[:key].to_s : "unregistered"
        AuditLog.log_action(
          action: ::Ai::Approvals::MachinePark::AUDIT_REFUSED, resource: account, account: account, source: "api",
          metadata: { requester_kind: "instance", node_instance_id: node_instance&.id.to_s.presence,
                      tool_action: routed_action_name(params), setting_key: registered,
                      action_category: self.class.declared_action(routed_action_name(params))&.dig(:action_category),
                      session_label: session_label, reason: code }.compact
        )
      rescue StandardError => e
        Rails.logger.error("[SiteSettingTool] park refusal audit row failed: #{e.class}: #{e.message}")
      end

      def key_spec(params)
        self.class.operator_configurable_keys[params[:key].to_s]
      end

      # THE ASYMMETRY THIS CLOSES (IMP-872269ef50a5). `protected_key?` was
      # consulted only on write doors — the REST twin's
      # `refuse_protected_key_write` and, below, `write_key_error`. Nothing
      # gated the read: `get_setting` checked only `key_spec`, and
      # `action_definitions` built site_setting_get's advertised key list
      # from every registered key, protected ones included. So registering a
      # key `protected: true` — meant to close its write door — simultaneously
      # OPENED its read: any admin.access holder could retrieve the value over
      # MCP, including from inside an agent conversation, where
      # Ai::AgentToolBridgeService runs the call as agent.creator, writes a
      # preview into ai_messages.processing_metadata (durable, never
      # re-filtered on read), and forwards the full JSON to the model provider
      # on the next turn. That sink is documented at length on
      # Ai::Tools::DiskImageOperatorTool and is exactly why this class is an
      # allowlist rather than a generic getter in the first place (see the
      # class comment) — a protected key sailed past that allowlist's own
      # rationale.
      #
      # THE CHOICE: refuse the read outright, full stop, for every caller —
      # not redact-and-serve, not "agents only". There is nothing to redact
      # onto (SiteSetting has no partial-value shape, and half a control-plane
      # guard value is still the guard value), and this tool has no notion of
      # "the caller is inside an agent conversation" to gate on selectively —
      # every dispatch, human MCP session or agent tool call, runs through the
      # same #call. A selective gate would need a signal this tool cannot see
      # without AgentToolBridgeService threading one through, which is a
      # bigger, riskier change for a key set that is small and rarely read
      # live. THE COST: an admin.access holder loses the ability to read a
      # protected key's CURRENT VALUE from an interactive MCP client. That is
      # not the operator's only read door — GET /api/v1/site_settings (and its
      # :show) is untouched by this refusal, is not routed through
      # AgentToolBridgeService or any conversation, and is the channel the
      # class's own `not_allowlisted_error` already directs operators to for
      # settings outside the allowlist entirely. So the working operator flow
      # (the settings UI) keeps working; only the MCP-conversation path closes.
      def read_key_error(params)
        return nil unless routed_action_name(params) == "site_setting_get"

        spec = key_spec(params)
        return nil unless spec && spec[:protected]

        error_result(
          "#{params[:key].to_s.inspect} is a protected setting: its value is not served over " \
          "MCP, even to an admin.access holder, because a tool result is persisted with the " \
          "conversation and forwarded to the model provider. Read its current value through the " \
          "operator REST API (GET /api/v1/site_settings) instead."
        )
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

        loosening = machine_request_tightening_refusal(params)
        return loosening if loosening

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
