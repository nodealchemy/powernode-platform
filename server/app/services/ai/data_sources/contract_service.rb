# frozen_string_literal: true

module Ai
  module DataSources
    # Aggregates a single "is the data contract met?" verdict for a fetch by
    # combining the three Phase 2b signals already present on a FetchEnvelope and
    # its endpoint: schema validity, quality outcome, and freshness (SLA).
    #
    # CONTRACT:
    #   Ai::DataSources::ContractService.new
    #     #validate(data_source:, endpoint:, envelope:) => {
    #       met: Boolean,
    #       schema_valid: (Boolean|nil),
    #       quality_passed: (Boolean|nil),
    #       within_sla: (Boolean|nil),
    #       violations: [<String>]
    #     }
    #
    # `envelope` is a QueryService FetchEnvelope (Hash). The three signals:
    #   - schema_valid : from envelope provenance (true/false, or nil-unknown when
    #     no response_schema is configured on the endpoint).
    #   - quality_passed : from the envelope/provenance quality fields when the
    #     QueryService quality stage ran, otherwise a FRESH QualityService run over
    #     the envelope's canonical records (nil only when neither is available).
    #   - within_sla : provenance cache_age_seconds vs endpoint.sla_max_age_seconds;
    #     TRUE when no SLA is configured (an unset SLA cannot be violated).
    #
    # met = all three signals hold: a nil signal (e.g. no schema configured /
    # quality genuinely unavailable) is treated as "not asserted" and does not
    # count as a violation, so a contract with no assertions is vacuously met.
    class ContractService
      def validate(data_source:, endpoint:, envelope:)
        env = envelope.is_a?(Hash) ? envelope : {}
        prov = provenance(env)

        schema_valid = schema_valid_signal(prov)
        quality_passed = quality_signal(env, prov, endpoint)
        within_sla = sla_signal(endpoint, prov)

        violations = []
        violations << "schema_invalid" if schema_valid == false
        violations << "quality_failed" if quality_passed == false
        violations << "sla_exceeded" if within_sla == false

        {
          met: violations.empty?,
          schema_valid: schema_valid,
          quality_passed: quality_passed,
          within_sla: within_sla,
          violations: violations
        }
      end

      private

      def provenance(env)
        prov = env[:provenance] || env["provenance"] || {}
        prov.is_a?(Hash) ? prov : {}
      end

      # schema_valid lives in provenance (true/false/nil-unknown).
      def schema_valid_signal(prov)
        fetch_indiff(prov, :schema_valid)
      end

      # quality_passed may ride on the envelope directly (when QueryService ran the
      # quality stage) or in provenance. When neither carries a verdict, fall back
      # to a FRESH QualityService run over the envelope's canonical records so a
      # contract check can stand alone even if quality was never evaluated inline.
      # nil only when the verdict is absent AND a fresh run is not possible.
      def quality_signal(env, prov, endpoint)
        value = fetch_indiff(env, :quality_passed)
        value = fetch_indiff(prov, :quality_passed) if value.nil?
        return value unless value.nil?

        fresh_quality(env, endpoint)
      end

      # Run QualityService over the envelope's canonical records (the `data` array).
      # Nil-safe: returns nil when no endpoint is available or the run cannot be
      # performed, so an unevaluable contract degrades to "not asserted" rather
      # than failing.
      def fresh_quality(env, endpoint)
        return nil unless endpoint

        records = fetch_indiff(env, :data) || []
        QualityService.new(endpoint).evaluate(records)[:passed]
      rescue StandardError => e
        Rails.logger.warn("[DataSources::ContractService] fresh quality run failed: #{e.message}")
        nil
      end

      # within_sla: cache age must be <= endpoint.sla_max_age_seconds. Returns TRUE
      # when no SLA is configured (an unset freshness budget cannot be exceeded),
      # and nil only when an SLA is set but the cache age is unknown.
      def sla_signal(endpoint, prov)
        sla = endpoint.respond_to?(:sla_max_age_seconds) ? endpoint.sla_max_age_seconds : nil
        return true if sla.nil?

        age = fetch_indiff(prov, :cache_age_seconds)
        return nil if age.nil?

        age.to_i <= sla.to_i
      end

      # Indifferent (symbol/string) fetch that distinguishes a missing key (nil)
      # from a present false.
      def fetch_indiff(hash, key)
        return hash[key] if hash.key?(key)
        return hash[key.to_s] if hash.key?(key.to_s)

        nil
      end
    end
  end
end
