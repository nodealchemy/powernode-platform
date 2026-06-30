# frozen_string_literal: true

module Ai
  module Security
    # G7 — periodic token-scope / permission-creep audit.
    #
    # Long-lived credentials and API tokens drift toward over-provisioning: a
    # scope added "just in case", a wildcard granted for a one-off, or an active
    # credential left wide open with no scope restriction at all. Nothing
    # reviews this on a cadence, so broad grants accumulate silently. This audit
    # reviews the access scopes on every active credential/token and flags the
    # over-broad ones so the periodic worker job (AiTokenScopeAuditJob) can alert.
    #
    # Audited subjects (platform-wide unless an account is given):
    #   * Ai::ProviderCredential#access_scopes — AI provider API credentials
    #   * ApiKey#scopes                         — platform API tokens
    #
    # CRYPTO-SAFE: findings carry ONLY subject ids, scope NAMES, and issue
    # descriptions. The secret/token material (encrypted_credentials, decrypted
    # api_key, key_digest) is never read or surfaced — scope names are not secrets.
    class TokenScopeAuditService
      # Scope names (after normalisation) that grant blanket / unrestricted access.
      BLANKET_SCOPES = %w[* all admin *:* superuser root owner].freeze

      # baseline: optional array of scope names considered acceptable. When given,
      #   any scope outside it is flagged as drift beyond the approved baseline.
      # account: optional Account to scope the audit to (platform-wide when nil,
      #   matching the other internal audits — gate_canary / process_scheduled).
      def initialize(account: nil, baseline: nil)
        @account  = account
        @baseline = baseline&.map { |s| normalize(s) }
      end

      # Returns { findings: [{ subject_type:, subject_id:, scopes:, issues: [..] }],
      #           over_provisioned_count: }.
      def run
        findings = audit_provider_credentials + audit_api_keys
        { findings: findings, over_provisioned_count: findings.size }
      end

      private

      def audit_provider_credentials
        relation = scoped(::Ai::ProviderCredential.active)
        relation.find_each.filter_map do |cred|
          finding_for("Ai::ProviderCredential", cred.id, cred.access_scopes)
        end
      end

      def audit_api_keys
        return [] unless defined?(::ApiKey)

        scoped(::ApiKey.active).find_each.filter_map do |key|
          finding_for("ApiKey", key.id, key.scopes)
        end
      end

      def scoped(relation)
        @account ? relation.where(account_id: @account.id) : relation
      end

      # Build a finding hash for an active subject when its scopes are
      # over-provisioned; nil otherwise.
      def finding_for(subject_type, subject_id, raw_scopes)
        names  = scope_names(raw_scopes)
        issues = scope_issues(names)
        return nil if issues.empty?

        { subject_type: subject_type, subject_id: subject_id, scopes: names, issues: issues }
      end

      def scope_issues(names)
        # Active + no scope restriction == unrestricted access == over-provisioned.
        return ["active credential has no scope restriction (unrestricted access)"] if names.empty?

        names.filter_map { |name| issue_for(name) }
      end

      def issue_for(name)
        norm = normalize(name)

        if BLANKET_SCOPES.include?(norm)
          "blanket scope grants unrestricted access: #{name}"
        elsif norm.end_with?("*")
          "wildcard scope is over-broad: #{name}"
        elsif norm.start_with?("admin", "all:")
          "administrative scope is over-broad: #{name}"
        elsif @baseline && !@baseline.include?(norm)
          "scope is outside the approved baseline: #{name}"
        end
      end

      def scope_names(raw_scopes)
        Array(raw_scopes).map { |s| s.to_s.strip }.reject(&:empty?)
      end

      def normalize(scope)
        scope.to_s.strip.downcase
      end
    end
  end
end
