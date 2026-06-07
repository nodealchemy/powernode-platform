# frozen_string_literal: true

module Ai
  module DataSources
    # Evaluates an endpoint's active data-quality expectations over a batch of
    # canonical records (the normalized Array<Hash> from QueryService).
    #
    # CONTRACT:
    #   Ai::DataSources::QualityService.new(endpoint)
    #     #evaluate(records) => {
    #       quality_score: Float(0..1),   # weighted share of rules passed
    #       passed: Boolean,              # false ONLY when an error-severity rule fails
    #       results: [{ name:, rule_type:, passed:, severity:, detail: }],
    #       anomalies: []                 # rule_type tokens of failed error-severity rules
    #     }
    #
    # When the endpoint has no active Ai::DataSourceExpectation rows, a couple of
    # sensible built-in defaults run (non-empty batch + uniform record shape) so a
    # quality signal still exists. Built-in defaults are WARN severity: they shape
    # the score but never fail the batch on their own.
    class QualityService
      # Error-severity rules can fail the batch; warn-severity only lowers score.
      SEVERITY_ERROR = "error"
      SEVERITY_WARN  = "warn"

      def initialize(endpoint)
        @endpoint = endpoint
      end

      # Run every active expectation (or the built-in defaults) over the records.
      # Always returns the full result Hash; never raises (a rule that blows up is
      # recorded as a failed warn-severity result rather than aborting the batch).
      def evaluate(records)
        recs = Array(records)
        rules = active_rules

        results = rules.map { |rule| safe_run(rule, recs) }

        {
          quality_score: weighted_score(results),
          passed: error_failures(results).empty?,
          results: results,
          anomalies: error_failures(results).map { |r| r[:rule_type] }.uniq
        }
      end

      private

      attr_reader :endpoint

      # The endpoint's active expectations, or built-in defaults when none are
      # configured. Each default is a lightweight Struct that quacks like an
      # expectation (name/rule_type/config/severity) for uniform handling.
      def active_rules
        configured = configured_expectations
        return configured if configured.any?

        default_rules
      end

      def configured_expectations
        return [] unless endpoint.respond_to?(:expectations)

        endpoint.expectations.respond_to?(:active) ? endpoint.expectations.active.to_a : []
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QualityService] could not load expectations: #{e.message}")
        []
      end

      DefaultRule = Struct.new(:name, :rule_type, :config, :severity, keyword_init: true)

      # Built-in WARN-severity sanity checks used when no expectations exist:
      #   - non_empty       : the batch returned at least one record
      #   - uniform_shape   : records share a consistent key set (schema-ish drift)
      def default_rules
        [
          DefaultRule.new(name: "non_empty", rule_type: "min_records", config: { "min" => 1 }, severity: SEVERITY_WARN),
          DefaultRule.new(name: "uniform_shape", rule_type: "distribution", config: {}, severity: SEVERITY_WARN)
        ]
      end

      # Execute one rule, trapping any error into a failed warn result so a single
      # bad rule definition cannot break the whole evaluation.
      def safe_run(rule, records)
        passed, detail = apply_rule(rule, records)
        {
          name: rule_name(rule),
          rule_type: rule_type(rule),
          passed: passed,
          severity: rule_severity(rule),
          detail: detail
        }
      rescue StandardError => e
        {
          name: rule_name(rule),
          rule_type: rule_type(rule),
          passed: false,
          severity: SEVERITY_WARN,
          detail: "rule error: #{e.message}"
        }
      end

      # Dispatch a rule to its checker. Returns [passed(Boolean), detail(String)].
      def apply_rule(rule, records)
        cfg = rule_config(rule)
        case rule_type(rule)
        when "required_fields" then check_required_fields(records, cfg)
        when "min_records"     then check_min_records(records, cfg)
        when "max_records"     then check_max_records(records, cfg)
        when "non_null"        then check_non_null(records, cfg)
        when "allowed_values"  then check_allowed_values(records, cfg)
        when "distribution"    then check_distribution(records, cfg)
        else [true, "unknown rule_type '#{rule_type(rule)}' — skipped"]
        end
      end

      # --- rule checkers ------------------------------------------------------

      def check_required_fields(records, cfg)
        fields = Array(cfg["fields"] || cfg["field"]).compact.map(&:to_s)
        return [true, "no fields configured"] if fields.empty?

        missing = records.each_with_index.flat_map do |rec, idx|
          h = to_hash(rec)
          fields.reject { |f| h.key?(f) }.map { |f| "record[#{idx}].#{f}" }
        end
        missing.empty? ? [true, "all required fields present"] : [false, "missing: #{missing.first(10).join(', ')}"]
      end

      def check_min_records(records, cfg)
        min = (cfg["min"] || cfg["minimum"] || 1).to_i
        records.size >= min ? [true, "#{records.size} >= #{min}"] : [false, "#{records.size} < #{min}"]
      end

      def check_max_records(records, cfg)
        return [true, "no max configured"] if cfg["max"].nil? && cfg["maximum"].nil?

        max = (cfg["max"] || cfg["maximum"]).to_i
        records.size <= max ? [true, "#{records.size} <= #{max}"] : [false, "#{records.size} > #{max}"]
      end

      def check_non_null(records, cfg)
        fields = Array(cfg["fields"] || cfg["field"]).compact.map(&:to_s)
        return [true, "no fields configured"] if fields.empty?

        nulls = records.each_with_index.flat_map do |rec, idx|
          h = to_hash(rec)
          fields.select { |f| blank_value?(h[f]) }.map { |f| "record[#{idx}].#{f}" }
        end
        nulls.empty? ? [true, "no null values in #{fields.join(', ')}"] : [false, "null: #{nulls.first(10).join(', ')}"]
      end

      def check_allowed_values(records, cfg)
        field = (cfg["field"] || Array(cfg["fields"]).first).to_s
        allowed = Array(cfg["values"] || cfg["allowed"])
        return [true, "no field/values configured"] if field.empty? || allowed.empty?

        violations = records.each_with_index.filter_map do |rec, idx|
          value = to_hash(rec)[field]
          next if value.nil? || allowed.include?(value)

          "record[#{idx}].#{field}=#{value.inspect}"
        end
        violations.empty? ? [true, "all values within allowed set"] : [false, "disallowed: #{violations.first(10).join(', ')}"]
      end

      # Distribution check: when a field is configured, the null/blank ratio of
      # that field must stay <= config["max_null_ratio"] (default 0.5). With NO
      # field configured it degrades to a record-shape uniformity check (the
      # built-in default): every record should share the most common key set.
      def check_distribution(records, cfg)
        field = (cfg["field"] || Array(cfg["fields"]).first).to_s
        return uniform_shape(records) if field.empty?

        return [true, "no records"] if records.empty?

        max_null_ratio = (cfg["max_null_ratio"] || 0.5).to_f
        null_count = records.count { |rec| blank_value?(to_hash(rec)[field]) }
        ratio = (null_count.to_f / records.size).round(4)
        ratio <= max_null_ratio ? [true, "null ratio #{ratio} <= #{max_null_ratio}"] : [false, "null ratio #{ratio} > #{max_null_ratio}"]
      end

      def uniform_shape(records)
        return [true, "empty batch"] if records.empty?

        keysets = records.map { |rec| to_hash(rec).keys.map(&:to_s).sort }
        common = keysets.group_by(&:itself).max_by { |_, v| v.size }&.first || []
        conforming = keysets.count { |ks| ks == common }
        if conforming == records.size
          [true, "all #{records.size} records share a consistent shape"]
        else
          [false, "#{records.size - conforming}/#{records.size} records deviate from the common shape"]
        end
      end

      # --- scoring ------------------------------------------------------------

      # quality_score = weighted share of rules that passed. Error-severity rules
      # weigh double so a passing-but-warn-heavy batch does not mask a failed
      # hard rule in the numeric score. Returns 1.0 when there are no rules.
      def weighted_score(results)
        return 1.0 if results.empty?

        total = results.sum { |r| weight_for(r[:severity]) }
        return 1.0 if total.zero?

        earned = results.sum { |r| r[:passed] ? weight_for(r[:severity]) : 0 }
        (earned.to_f / total).round(4)
      end

      def weight_for(severity)
        severity.to_s == SEVERITY_ERROR ? 2 : 1
      end

      def error_failures(results)
        results.select { |r| r[:severity].to_s == SEVERITY_ERROR && r[:passed] == false }
      end

      # --- duck-typed rule accessors (AR record OR DefaultRule) ---------------

      def rule_name(rule)
        rule.respond_to?(:name) ? rule.name.to_s : "rule"
      end

      def rule_type(rule)
        rule.respond_to?(:rule_type) ? rule.rule_type.to_s : ""
      end

      def rule_severity(rule)
        sev = rule.respond_to?(:severity) ? rule.severity.to_s : SEVERITY_WARN
        sev.empty? ? SEVERITY_WARN : sev
      end

      def rule_config(rule)
        cfg = rule.respond_to?(:config) ? rule.config : {}
        cfg.is_a?(Hash) ? cfg.with_indifferent_access : {}
      rescue StandardError
        {}
      end

      # --- small helpers ------------------------------------------------------

      def to_hash(record)
        return record if record.is_a?(Hash)
        return record.to_h if record.respond_to?(:to_h)

        {}
      rescue StandardError
        {}
      end

      def blank_value?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
