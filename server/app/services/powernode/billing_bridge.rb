# frozen_string_literal: true

module Powernode
  # Core-side extension point for optional billing capabilities.
  #
  # Core never references the business `Billing::` namespace directly. The business
  # extension registers its models + handlers here at boot; when no extension is
  # present every accessor degrades safely (nil models, quota always allowed).
  #
  # This replaces the previous `defined?(Billing::X)` guards scattered through core
  # dashboards/controllers with a single clean interface.
  module BillingBridge
    # The one denial contract. EVERY producer of a provisioning denial emits
    # exactly these keys, always present — nil where a value is unknown, never
    # absent — so a consumer (the frontend `UpgradeRequiredCard`) never has to
    # branch on which producer denied, nor distinguish "absent" from "unknown".
    UPGRADE_PAYLOAD_KEYS = %i[requires_upgrade reason cap upgrade_url].freeze

    # Reason emitted when the quota handler itself failed, so an operator can
    # tell "you are over your plan limit" from "we could not check your plan
    # limit". Deliberately not one of the plan-limit reasons.
    DEGRADED_QUOTA_REASON = "quota_check_unavailable"

    # Postures a caller may select for a handler failure.
    ON_ERROR_MODES = %i[deny allow].freeze

    class << self
      # Model classes registered by the business extension (nil in core mode).
      attr_accessor :subscription_model, :payment_model, :plan_model, :revenue_snapshot_model

      # Handler registered by the business extension to enforce provisioning quota.
      # A callable taking (account:, mission:) and returning a Hash:
      #   { allowed: true } or { allowed: false, payload: {...} }
      attr_writer :provisioning_quota_handler

      def provisioning_quota_handler
        @provisioning_quota_handler
      end

      # Build a denial payload in the canonical shape. The single definition of
      # UPGRADE_PAYLOAD_KEYS — producers call this rather than assembling a hash
      # literal, which is how the two shapes diverged in the first place.
      # A blank reason would render as the generic "Hit your plan's limit" card
      # — a false statement to a user whose denial we cannot explain. Fall back
      # to the degraded reason, which says so honestly and shows no upsell.
      def upgrade_payload(reason:, cap: nil, upgrade_url: nil)
        text = reason.to_s
        text = DEGRADED_QUOTA_REASON if text.empty?
        { requires_upgrade: true, reason: text, cap: cap, upgrade_url: upgrade_url }
      end

      # Enforce provisioning quota via the registered handler.
      #
      # FAILURE POSTURE — fails CLOSED. A guard that answers "allowed" when it
      # errors is not a guard: the sole caller proceeds to provision real,
      # billable infrastructure, so a transient billing-side error would become
      # unmetered spend with nothing but a log line to show for it. A false deny
      # costs a retry; a false allow costs money that is never recovered.
      #
      # Degraded-open is still available, but only as the CALLER's explicit
      # choice (`on_error: :allow`) — never as a silent default in a rescue.
      #
      # No handler registered is NOT a failure: it is core mode (no billing
      # extension, therefore no quota limits) and still allows.
      #
      # @param on_error [:deny, :allow] posture when the handler raises
      # @return [Hash] { allowed: Boolean, payload: Hash (present only on denial) }
      def check_provisioning_quota(account:, mission:, on_error: :deny)
        # Validated BEFORE the handler runs, and outside the rescue below, so a
        # typo'd mode can never be swallowed by the very rescue it selects.
        unless ON_ERROR_MODES.include?(on_error)
          raise ArgumentError,
                "on_error must be one of #{ON_ERROR_MODES.inspect}, got #{on_error.inspect}"
        end

        return { allowed: true } unless @provisioning_quota_handler

        begin
          normalize_quota_verdict(
            @provisioning_quota_handler.call(account: account, mission: mission),
            on_error: on_error
          )
        rescue StandardError => e
          Rails.logger.error(
            "[Powernode::BillingBridge] provisioning quota handler failed " \
            "(#{e.class}): #{e.message}; on_error=#{on_error}"
          )
          degraded_verdict(on_error)
        end
      end

      # Test/boot helper.
      def reset!
        @subscription_model = nil
        @payment_model = nil
        @plan_model = nil
        @revenue_snapshot_model = nil
        @provisioning_quota_handler = nil
      end

      private

      # Force every denial the bridge emits onto the canonical contract,
      # whatever the handler chose to return. Handler-supplied values win;
      # missing contract keys are filled with nil; any EXTRA diagnostic keys
      # the handler supplied are preserved rather than silently dropped.
      def normalize_quota_verdict(verdict, on_error:)
        # A handler that returns something other than a verdict Hash is a BROKEN
        # handler. It lands on the same posture as one that raises, rather than
        # slipping past the contract to blow up in the caller.
        return degraded_verdict(on_error) unless verdict.is_a?(Hash)

        # `allowed` gets the same symbol/string tolerance as the payload, and an
        # EXPLICIT true test rather than Ruby truthiness: a handler returning
        # `allowed: "false"` would otherwise read as permission to provision —
        # a fail-open straight through the guard that is meant to close.
        # Restamp the symbol key so a string-keyed allow is readable as one:
        # every caller reads `result[:allowed]`.
        return verdict.merge(allowed: true) if fetch_either(verdict, :allowed) == true

        supplied = fetch_either(verdict, :payload) || {}
        canonical = upgrade_payload(
          reason: fetch_either(supplied, :reason),
          cap: fetch_either(supplied, :cap),
          upgrade_url: fetch_either(supplied, :upgrade_url)
        )
        verdict.merge(allowed: false, payload: supplied.merge(canonical))
      end

      # A handler may hand back string keys (JSON round-trip, a hash built from
      # params). Reading only the symbol would null out the canonical key while
      # leaving the real value stranded under its string twin.
      def fetch_either(hash, key)
        hash[key].nil? ? hash[key.to_s] : hash[key]
      end

      def degraded_verdict(on_error)
        return { allowed: true } if on_error == :allow

        { allowed: false, payload: upgrade_payload(reason: DEGRADED_QUOTA_REASON) }
      end
    end
  end
end
