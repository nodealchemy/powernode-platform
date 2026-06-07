# frozen_string_literal: true

module Ai
  module DataSources
    # Query-time governance for the data-source fetch pipeline (Phase 4b-2b).
    #
    # PURPOSE
    #   Two responsibilities, both invoked PER REQUEST from QueryService:
    #     1. #authorize — decide whether THIS agent (or user/system context) is
    #        allowed to read THIS data source right now, combining per-agent ABAC
    #        (Ai::AgentPrivilegePolicy) with account-level data-access compliance
    #        policies (Ai::CompliancePolicy: residency / consent / usage policy).
    #     2. #mask_records — redact PII/secret material out of the response records
    #        according to the source's configured classification, using the shared
    #        Ai::Security::PiiRedactionService masking primitive.
    #
    # REUSE (this service invents NO new models and NO new policy engine)
    #   * Ai::AgentPrivilegePolicy.applicable_to(agent_id, trust_tier) +
    #     #resource_allowed?("data_source:<id>") — the existing per-agent ABAC grant
    #     check (allowed_resources / denied_resources, wildcard-aware).
    #   * Ai::CompliancePolicy.active.by_type("data_access") + #applies_to? +
    #     #evaluate(context) + #blocking? + #record_violation! — the existing
    #     compliance evaluation + violation-recording surface.
    #   * Ai::Security::PiiRedactionService#redact(log: false) — the existing
    #     redact-all-detected masking primitive (strips every detected PII/secret
    #     pattern, silently; we never log PII material ourselves).
    #
    # CONFIG IS MIGRATION-FREE
    #   Governance config is read from EXISTING jsonb columns on the data source:
    #     * data_source.metadata["governance"] — { "classification", "mask",
    #       "mask_at_classification", "region" / "residency" } (string OR symbol
    #       keys tolerated).
    #     * data_source.configuration["mtls"] — client-cert material (read elsewhere
    #       in the pipeline; surfaced here only as part of the residency context).
    #
    # POSTURE: FAIL-OPEN ON INFRA ERROR, DENY ON EXPLICIT POLICY
    #   A policy-engine BUG (a raised exception while resolving or evaluating
    #   policies) must never break read fetches — those rescue to allowed:true and
    #   log the error CLASS only. This is deliberate: governance is an overlay on a
    #   read path that already authorized the human via controller permissions; an
    #   internal fault should degrade to "allow + log", not "hard-fail every query".
    #   An EXPLICIT policy decision is the opposite: when an applicable privilege
    #   policy explicitly DENIES this resource, or a BLOCKING compliance policy
    #   returns allowed:false, #authorize returns allowed:false. Infra error => open;
    #   explicit deny => closed.
    #
    # ABAC DEFAULT-ALLOW POSTURE (documented intentionally)
    #   The per-agent grant model is DENY-ON-EXPLICIT, not require-explicit-grant:
    #   if NO applicable privilege policy mentions "data_source:<id>" at all (it is
    #   absent from both allowed_resources and denied_resources, with no wildcard),
    #   the request is ALLOWED. This keeps existing fetches working when no operator
    #   has authored a resource-scoped policy yet. A request is denied ONLY when an
    #   applicable policy explicitly lists the resource (or "*") under
    #   denied_resources. (Note: AgentPrivilegePolicy#resource_allowed? already
    #   returns true for a non-mentioning policy because allowed_resources is empty;
    #   we additionally treat "policy never mentions the resource" as a no-op so a
    #   single permissive policy cannot accidentally grant-away nothing.)
    #
    # MASKING IS POST-CACHE, PER-REQUEST
    #   QueryService caches RAW (unmasked) records — masking is applied at the single
    #   envelope-finalization chokepoint, AFTER a cache hit or fresh decode, so the
    #   cache is classification-agnostic and the same cached payload can be masked
    #   differently per requester/policy without poisoning the shared cache entry.
    #
    # CONTRACT
    #   Ai::DataSources::GovernanceService
    #     .new(data_source:, agent:, account:)
    #     #authorize(context: {}) => { allowed:, reason:, enforcement: }
    #     #mask_records(records)  => { records:, masking_applied:, masked_count: }
    class GovernanceService
      # The privilege-policy resource token for a data source. ABAC grants/denies
      # are expressed against "data_source:<uuid>".
      RESOURCE_PREFIX = "data_source"

      # Compliance policies governing read access to external data.
      COMPLIANCE_TYPE = "data_access"

      # Map a numeric trust_score (0..1) to a trust tier. Mirrors
      # Ai::AgentTrustScore::TIER_THRESHOLDS so a numeric score and a tiered record
      # resolve identically. Kept local (not a hard dependency on the model
      # constant) so a missing/altered model never breaks resolution.
      TIER_THRESHOLDS = {
        "autonomous" => 0.9,
        "trusted" => 0.7,
        "monitored" => 0.4,
        "supervised" => 0.0
      }.freeze
      DEFAULT_TRUST_TIER = "supervised"

      # Hard ceiling on how many string values we will redact in a single response
      # to keep per-request masking bounded on pathological payloads. Beyond this we
      # stop walking and flag the truncation rather than blocking the response.
      MAX_MASKED_VALUES = 50_000

      def initialize(data_source:, agent:, account:)
        @data_source = data_source
        @agent = agent
        @account = account
      end

      # ----------------------------------------------------------------------
      # (a) AUTHORIZE — ABAC (per-agent) + compliance (residency/consent)
      # ----------------------------------------------------------------------

      # Decide whether the current principal may read @data_source.
      #
      # Returns { allowed: Boolean, reason: String|nil, enforcement: String|nil }.
      #
      #   * User/system context (agent nil): the controller already authorized the
      #     human via permissions, so agent ABAC is skipped and we allow (compliance
      #     residency/consent still applies — a data-access block is account-wide,
      #     not agent-specific).
      #   * ABAC: deny if any applicable Ai::AgentPrivilegePolicy explicitly denies
      #     "data_source:<id>". Default-allow when no policy mentions the resource.
      #   * Compliance: deny if a BLOCKING data_access policy that #applies_to? this
      #     source returns allowed:false (and record the violation). Non-blocking
      #     (log/warn) policies are logged, never denied.
      #   * Fail-open on infra error: a raised exception while resolving/evaluating
      #     policies degrades to allowed:true (logged), but an explicit policy deny
      #     returns allowed:false.
      def authorize(context: {})
        ctx = (context || {}).to_h

        # Zero-overhead default: a user/system fetch (agent nil) of a source with NO
        # governance config skips ALL policy resolution — the controller already
        # authorized the human and there is nothing source-specific to enforce. Agent
        # fetches and governance-configured sources still run the full check below, so
        # account-wide data_access compliance applies to every agent-initiated read.
        return allow if agent.nil? && governance_config.blank?

        abac = authorize_abac
        return abac unless abac[:allowed]

        compliance = authorize_compliance(ctx)
        return compliance unless compliance[:allowed]

        { allowed: true, reason: nil, enforcement: nil }
      rescue StandardError => e
        # FAIL-OPEN on an INFRA error only (policy-engine bug). Log the class — never
        # the message/material — and allow the read so a governance fault cannot
        # break the fetch pipeline. Explicit denies were already returned above.
        Rails.logger.error(
          "[DataSources::GovernanceService] authorize fail-open (#{e.class}) for #{safe_slug}"
        )
        { allowed: true, reason: nil, enforcement: nil }
      end

      # ----------------------------------------------------------------------
      # (b) MASK — redact PII/secret values out of the response records
      # ----------------------------------------------------------------------

      # Mask string VALUES in the records when the source opts into masking.
      #
      # Returns { records:, masking_applied: Boolean, masked_count: Integer }.
      #
      #   * OFF (records returned unchanged, masking_applied:false) unless the source
      #     governance config requests it: metadata.governance.mask truthy, OR a
      #     classification / mask_at_classification level is configured.
      #   * ON: deep-walk every Hash/Array, and for every STRING value run the shared
      #     PiiRedactionService#redact(log: false) — which strips EVERY detected
      #     PII/secret pattern (not a classification-threshold subset) — replacing the
      #     value with its redacted_text and counting masked fields. Keys are never
      #     masked; non-string scalars are untouched. The redaction service is
      #     instantiated ONCE for the whole walk.
      #   * Runs per-request on the FINAL records (cache holds RAW), so it must be
      #     fast — pathological payloads are capped at MAX_MASKED_VALUES.
      def mask_records(records)
        return passthrough(records) unless masking_enabled?
        return passthrough(records) if records.blank?

        masked_count = 0
        truncated = false

        masked = deep_mask(records) do |value|
          if masked_count >= MAX_MASKED_VALUES
            truncated = true
            next value
          end

          # Use #redact (redact-ALL-detected, log:false) — NOT #apply_policy.
          # apply_policy threshold-filters by classification (so a secret can slip
          # through at a permissive level) AND writes a policy-enforcement audit row
          # PER value — a write-amplification storm on a large response. #redact
          # strips every detected PII/secret pattern and is silent, which is exactly
          # the conservative per-value egress masking we want here.
          redacted = redaction_service.redact(
            text: value,
            context: masking_context,
            log: false
          )[:redacted_text]

          masked_count += 1 if redacted != value
          redacted
        end

        if truncated
          Rails.logger.warn(
            "[DataSources::GovernanceService] masking capped at #{MAX_MASKED_VALUES} values for #{safe_slug}"
          )
        end

        { records: masked, masking_applied: true, masked_count: masked_count }
      rescue StandardError => e
        # A masking fault must NOT leak unmasked data downstream NOR break the
        # response. Fail CLOSED on content but OPEN on availability: drop string
        # values to a generic placeholder is too lossy, so instead we surface the
        # original records but flag masking as not-applied so callers/provenance can
        # see masking did not run. Log the class only (never the content).
        Rails.logger.error(
          "[DataSources::GovernanceService] masking error (#{e.class}) for #{safe_slug}"
        )
        passthrough(records)
      end

      private

      attr_reader :data_source, :agent, :account

      # ======================================================================
      # ABAC
      # ======================================================================

      # Per-agent attribute-based access control. Returns a decision Hash.
      # User/system context (no agent) skips ABAC entirely and allows.
      def authorize_abac
        return allow unless agent&.id

        resource = resource_token
        policies = Ai::AgentPrivilegePolicy.applicable_to(agent.id, agent_trust_tier).to_a

        # DENY only on an EXPLICIT deny of this resource by any applicable policy.
        # Default-allow when no policy mentions the resource (see class doc).
        denying = policies.find { |policy| explicit_deny?(policy, resource) }
        if denying
          return {
            allowed: false,
            reason: "Privilege policy '#{denying.policy_name}' denies #{resource}",
            enforcement: "block"
          }
        end

        allow
      rescue StandardError => e
        Rails.logger.error(
          "[DataSources::GovernanceService] ABAC fail-open (#{e.class}) for #{safe_slug}"
        )
        allow
      end

      # True when this privilege policy EXPLICITLY denies the resource — the
      # resource (or "*") appears in denied_resources. This is the only condition
      # that produces a deny; a policy that merely fails to grant the resource is a
      # no-op under the default-allow posture. Wildcard-aware via the model's own
      # #resource_allowed? for the affirmative case, but we gate on an explicit
      # mention so an empty/permissive policy cannot deny.
      def explicit_deny?(policy, resource)
        denied = Array(policy.denied_resources)
        return true if denied.include?("*")
        return true if denied.include?(resource)

        false
      end

      # ======================================================================
      # COMPLIANCE (residency / consent / usage policy)
      # ======================================================================

      # Evaluate every active data_access compliance policy that applies to this
      # source. A BLOCKING policy returning allowed:false denies the read (and the
      # violation is recorded). Non-blocking policies are logged, never denied.
      def authorize_compliance(context)
        merged = compliance_context(context)

        # Highest-priority (and blocking) policies first, so a hard block is reached
        # before advisory ones.
        policies = Ai::CompliancePolicy.active.by_type(COMPLIANCE_TYPE).ordered_by_priority.to_a
        policies.each do |policy|
          next unless policy_applies?(policy, data_source)

          decision = policy.evaluate(merged)
          next if decision[:allowed]

          if policy.blocking?
            record_compliance_violation(policy, decision)
            return {
              allowed: false,
              reason: decision[:reason] || "Compliance policy '#{policy.name}' denied access",
              enforcement: decision[:enforcement] || "block"
            }
          else
            # Non-blocking (log/warn/require_approval handled elsewhere): record the
            # advisory outcome but do not deny the read here.
            Rails.logger.info(
              "[DataSources::GovernanceService] non-blocking compliance '#{policy.name}' " \
              "flagged #{safe_slug}: #{decision[:reason]}"
            )
          end
        end

        allow
      rescue StandardError => e
        Rails.logger.error(
          "[DataSources::GovernanceService] compliance fail-open (#{e.class}) for #{safe_slug}"
        )
        allow
      end

      # Guard CompliancePolicy#applies_to? — it reads resource.class.name + tags, so
      # a malformed policy must not abort the whole evaluation.
      def policy_applies?(policy, resource)
        policy.applies_to?(resource)
      rescue StandardError => e
        Rails.logger.warn(
          "[DataSources::GovernanceService] applies_to? check failed (#{e.class}) for #{safe_slug}"
        )
        false
      end

      # Build the context Hash handed to CompliancePolicy#evaluate. Carries the
      # source's data-residency/region (from metadata.governance), the agent's trust
      # tier, the account id, and the mTLS posture so residency/consent conditions
      # can match. Caller-supplied context wins on key collision.
      def compliance_context(caller_context)
        {
          region: governance_region,
          residency: governance_residency,
          data_residency: governance_residency,
          classification: governance_classification,
          agent_trust_tier: agent_trust_tier,
          account_id: account&.id,
          data_source_id: data_source&.id,
          data_source_slug: (data_source.respond_to?(:slug) ? data_source.slug : nil),
          mtls: mtls_present?
        }.merge(caller_context.transform_keys(&:to_sym))
      end

      def record_compliance_violation(policy, decision)
        policy.record_violation!(
          source_type: "data_source",
          source_id: data_source&.id,
          description: decision[:reason] || "Data-access compliance violation on #{safe_slug}",
          context: {
            "data_source_slug" => (data_source.respond_to?(:slug) ? data_source.slug : nil),
            "region" => governance_region,
            "residency" => governance_residency,
            "agent_trust_tier" => agent_trust_tier,
            "enforcement" => decision[:enforcement]
          }.compact,
          severity: "high"
        )
      rescue StandardError => e
        # Recording a violation must never turn a clean deny into a crash.
        Rails.logger.warn(
          "[DataSources::GovernanceService] violation record failed (#{e.class}) for #{safe_slug}"
        )
      end

      # ======================================================================
      # MASKING helpers
      # ======================================================================

      # Masking is ON when the source explicitly opts in via metadata.governance:
      # a truthy "mask", or any configured classification / mask_at_classification
      # level. OFF (default) otherwise — so a source with no governance config has
      # zero masking overhead and byte-for-byte unchanged behavior.
      def masking_enabled?
        gov = governance_config
        return false if gov.blank?

        # Masking is an EXPLICIT opt-in: a truthy "mask", or a "mask_at_classification"
        # marker. A bare "classification" label (used only for the compliance context)
        # does NOT by itself turn on egress masking — labeling a source's sensitivity
        # and stripping values from its payload are separate decisions.
        return true if truthy?(jget(gov, "mask"))
        return true if jget(gov, "mask_at_classification").present?

        false
      end

      # Deep-walk a record structure, yielding every STRING value to the block and
      # substituting the block's return. Hashes and Arrays are rebuilt; keys are
      # left untouched; non-string scalars pass through unchanged.
      def deep_mask(value, &block)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), acc|
            acc[k] = deep_mask(v, &block)
          end
        when Array
          value.map { |v| deep_mask(v, &block) }
        when String
          block.call(value)
        else
          value
        end
      end

      # Build the redaction service ONCE per masking call (it is the heavy object).
      def redaction_service
        @redaction_service ||= Ai::Security::PiiRedactionService.new(account: account)
      end

      def masking_context
        {
          source_type: "DataSourceQuery",
          field_path: "response_record",
          data_source_id: data_source&.id
        }
      end

      def passthrough(records)
        { records: records, masking_applied: false, masked_count: 0 }
      end

      # ======================================================================
      # governance config readers (migration-free; string OR symbol keys)
      # ======================================================================

      # data_source.metadata["governance"] — the classification + masking +
      # residency block. Tolerates string OR symbol keys at both levels.
      def governance_config
        @governance_config ||= begin
          meta = data_source.respond_to?(:metadata) ? data_source.metadata : nil
          gov = meta.is_a?(Hash) ? (meta["governance"] || meta[:governance]) : nil
          gov.is_a?(Hash) ? gov : {}
        end
      rescue StandardError
        {}
      end

      def governance_classification
        jget(governance_config, "classification")
      end

      # Data residency / region for compliance evaluation. "region" and "residency"
      # are accepted spellings; either populates both context keys.
      def governance_region
        jget(governance_config, "region") || jget(governance_config, "residency")
      end

      def governance_residency
        jget(governance_config, "residency") || jget(governance_config, "region")
      end

      # data_source.configuration["mtls"] — client-cert config. We only surface
      # whether it is present (boolean) into the compliance context; the cert
      # material itself is consumed by the connection layer, never read here.
      def mtls_present?
        cfg = data_source.respond_to?(:configuration) ? data_source.configuration : nil
        mtls = cfg.is_a?(Hash) ? (cfg["mtls"] || cfg[:mtls]) : nil
        mtls.is_a?(Hash) ? mtls.present? : truthy?(mtls)
      rescue StandardError
        false
      end

      # ======================================================================
      # trust tier resolution
      # ======================================================================

      # Resolve the agent's trust tier for AgentPrivilegePolicy.applicable_to and
      # the compliance context. Handles every shape the agent might expose:
      #   * #trust_tier (string)            -> used directly
      #   * #trust_level (string column)    -> used directly
      #   * #trust_score returning a record (responds to #tier) -> record.tier
      #   * #trust_score returning a Numeric (0..1) -> mapped via TIER_THRESHOLDS
      # Falls back to DEFAULT_TRUST_TIER ("supervised") so a missing signal yields
      # the most restrictive tier rather than nil.
      def agent_trust_tier
        return DEFAULT_TRUST_TIER unless agent

        if agent.respond_to?(:trust_tier) && agent.trust_tier.present?
          return agent.trust_tier.to_s
        end

        if agent.respond_to?(:trust_score)
          score = agent.trust_score
          return score.tier.to_s if score.respond_to?(:tier) && score.tier.present?
          return tier_for_score(score) if score.is_a?(Numeric)
        end

        if agent.respond_to?(:trust_level) && agent.trust_level.present?
          return agent.trust_level.to_s
        end

        DEFAULT_TRUST_TIER
      rescue StandardError
        DEFAULT_TRUST_TIER
      end

      # Map a numeric 0..1 score to the highest tier whose threshold it meets.
      def tier_for_score(score)
        TIER_THRESHOLDS.each do |tier, threshold|
          return tier if score.to_f >= threshold
        end
        DEFAULT_TRUST_TIER
      end

      # ======================================================================
      # small helpers
      # ======================================================================

      def resource_token
        "#{RESOURCE_PREFIX}:#{data_source&.id}"
      end

      def allow
        { allowed: true, reason: nil, enforcement: nil }
      end

      # Read a key from a jsonb-sourced Hash tolerating string OR symbol keys.
      def jget(hash, key)
        return nil unless hash.is_a?(Hash)

        hash[key.to_s].nil? ? hash[key.to_sym] : hash[key.to_s]
      end

      def truthy?(value)
        return false if value.nil?
        return value if value == true || value == false

        %w[true 1 yes on].include?(value.to_s.strip.downcase)
      end

      def safe_slug
        data_source.respond_to?(:slug) ? data_source.slug.to_s : "unknown"
      rescue StandardError
        "unknown"
      end
    end
  end
end
