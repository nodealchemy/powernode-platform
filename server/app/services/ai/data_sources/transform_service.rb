# frozen_string_literal: true

module Ai
  module DataSources
    # Config-driven, agent-usable shaping of the canonical data-source records.
    #
    # Runs an ORDERED transform PIPELINE over the canonical Array<Hash> records
    # (the output of NormalizationService). Each step is a Hash declaring an "op"
    # plus op-specific keys; steps are applied IN ORDER, the output of one feeding
    # the next.
    #
    # Usage (mirrors NormalizationService's .new(config).apply(records) shape):
    #
    #   transformed = TransformService.new(transforms_config).apply(records)
    #
    # `transforms_config` shape:
    #
    #   { "pipeline" => [
    #       { "op" => "flatten", "separator" => ".", "only" => [...], "except" => [...] },
    #       { "op" => "unnest",  "field" => "items" },               # alias "explode"
    #       { "op" => "select",  "fields" => ["a", "b"] },           # alias "project"
    #       { "op" => "select",  "drop" => ["secret"] },
    #       { "op" => "rename",  "map" => { "from" => "to" } },
    #       { "op" => "computed","as" => "full", "fn" => "concat",    # inner op in "fn"
    #                            "fields" => ["first", "last"], "separator" => " " }
    #   ] }
    #
    # Blank config, a non-Hash config, or a config with no/empty "pipeline" is a
    # PASSTHROUGH: the records are returned unchanged.
    #
    # SUPPORTED OPS (any other "op" is a no-op: the step is skipped and a debug
    # line is logged — unknown ops are NEVER executed):
    #
    #   - "flatten": flatten nested hashes to dotted keys
    #       {"a"=>{"b"=>1}} -> {"a.b"=>1}. Config "separator" (default "."),
    #       optional "only"/"except" TOP-LEVEL field lists to scope which keys are
    #       descended into.
    #   - "unnest" (alias "explode"): config "field" pointing at an Array value ->
    #       emit ONE record per element. A Hash element is merged with the parent's
    #       OTHER fields; a scalar element is placed under a "value" key alongside
    #       the parent's other fields. Records lacking an Array at "field" pass
    #       through unchanged. BOUNDED: total output is capped at MAX_RECORDS to
    #       avoid fan-out blowups (the overflow is dropped and the cap is logged).
    #   - "select" (alias "project"): config "fields" (keep ONLY these) OR "drop"
    #       (remove these). "fields" wins if both are given.
    #   - "rename": config "map" {from=>to}; renames matching keys, leaving others.
    #   - "computed": config "as" (new field name) + a whitelisted "op" reading
    #       ONLY existing record fields (see COMPUTED OPS). The result is written to
    #       the "as" field.
    #
    # COMPUTED OPS (the value of the step's "op" when the step op is "computed";
    # the op token is read from "op" — when "op" == "computed" the inner op is read
    # from "fn"/"operation"/"compute" as a fallback so a single "op" key can carry
    # either, see #computed_op_for):
    #
    #   - "concat":    join "fields" (existing field names) with optional
    #                  "separator" (default "").
    #   - "coalesce":  first non-nil/non-blank of "fields".
    #   - "+","-","*","/": arithmetic over two numeric operands taken from "a"/"b"
    #                  or the first two entries of "fields". Division by zero -> nil.
    #   - "upcase"/"downcase"/"strip": string op on a single "field".
    #   - "substring" (alias "slice"): "field" + "start" + "length".
    #   - "template" (alias "format"): "template" like "{a}-{b}", interpolating
    #                  existing fields by name ({missing} -> "").
    #
    # SECURITY (ABSOLUTE): the "computed" op is a WHITELISTED mini-interpreter over
    # the named operations above, reading ONLY existing record fields. It NEVER
    # uses eval / instance_eval / class_eval / send / public_send to arbitrary
    # methods / Kernel — there is NO arbitrary code execution from config. Every
    # operation is dispatched through an explicit case statement; an unrecognized
    # op is skipped (no-op), never executed.
    #
    # RUNS PRE-CACHE: this service runs AFTER normalization and BEFORE the response
    # cache write, and is deterministic given (config, records), so the cached
    # payload is already the TRANSFORMED shape (no per-read transform cost).
    #
    # RESILIENCE: pure / stateless — no DB, Redis, or network. A malformed step is
    # skipped (logged at warn) and never raises out of #apply; #apply itself is
    # fully rescued and returns the best records it has on any unexpected fault.
    class TransformService
      # Hard cap on records emitted by an "unnest"/"explode" step so a pathological
      # array (or a chain of them) cannot blow up memory. Overflow is dropped.
      MAX_RECORDS = 50_000

      # Max nesting depth flatten will descend before writing the remaining subtree
      # as a terminal value. Bounds stack depth so a pathologically/maliciously deep
      # upstream hash cannot raise SystemStackError.
      MAX_FLATTEN_DEPTH = 32

      # Max pipeline steps honored; excess steps are dropped (logged). Bounds the
      # per-request transform cost from an oversized config.
      MAX_PIPELINE_STEPS = 100

      # Default join separator for flatten dotted keys.
      DEFAULT_SEPARATOR = "."

      # Arithmetic computed ops.
      ARITHMETIC_OPS = %w[+ - * /].freeze

      def initialize(transforms_config = {})
        @config = normalize_config(transforms_config)
      end

      # Apply the ordered pipeline to the canonical records.
      #
      # @param records [Array<Hash>] canonical, normalized records (string OR
      #   symbol keys tolerated).
      # @return [Array<Hash>] the transformed records. Passthrough (the input,
      #   coerced to an Array) when the config is blank / has no pipeline.
      def apply(records)
        rows = coerce_rows(records)
        return rows unless enabled?

        pipeline.reduce(rows) do |current, step|
          apply_step(step, current)
        end
      rescue StandardError => e
        Rails.logger.warn("[DataSources::TransformService] pipeline aborted, returning best-effort records: #{e.class}: #{e.message}")
        coerce_rows(records)
      end

      # True when a non-empty pipeline is configured (mirrors the model predicate).
      def enabled?
        pipeline.any?
      end

      private

      attr_reader :config

      # Coerce the input to an Array of records. A bare Hash is treated as a SINGLE
      # record ([hash]) — NOT Array(hash), which Ruby would explode into [[k,v],...].
      def coerce_rows(records)
        case records
        when Array then records
        when Hash  then [records]
        when nil   then []
        else Array(records)
        end
      end

      def pipeline
        @pipeline ||= begin
          steps = Array(config["pipeline"]).select { |s| s.is_a?(Hash) }
          if steps.size > MAX_PIPELINE_STEPS
            Rails.logger.warn(
              "[DataSources::TransformService] pipeline truncated to #{MAX_PIPELINE_STEPS} steps (had #{steps.size})"
            )
            steps = steps.first(MAX_PIPELINE_STEPS)
          end
          steps
        end
      end

      # Dispatch a single pipeline step. Each op is isolated: a step that raises is
      # logged and SKIPPED (the records flow through unchanged), so one bad step
      # never aborts the whole pipeline.
      def apply_step(step, rows)
        op = step_op(step)
        case op
        when "flatten"            then op_flatten(step, rows)
        when "unnest", "explode"  then op_unnest(step, rows)
        when "select", "project"  then op_select(step, rows)
        when "rename"             then op_rename(step, rows)
        when "computed"           then op_computed(step, rows)
        else
          Rails.logger.debug { "[DataSources::TransformService] skipping unknown op #{op.inspect}" }
          rows
        end
      rescue StandardError => e
        Rails.logger.warn("[DataSources::TransformService] step #{step_op(step).inspect} failed, skipping: #{e.class}: #{e.message}")
        rows
      end

      # ---- flatten ----------------------------------------------------------

      # Flatten nested hashes into dotted keys, per record. "only"/"except" scope
      # which TOP-LEVEL keys are descended into; non-hash values are left as-is.
      def op_flatten(step, rows)
        sep = separator(step)
        only = string_list(step["only"])
        except = string_list(step["except"])

        map_records(rows) do |record|
          flatten_record(record, sep, only, except)
        end
      end

      def flatten_record(record, sep, only, except)
        record.each_with_object({}) do |(key, value), out|
          k = key.to_s
          descend = value.is_a?(Hash) &&
                    (only.empty? || only.include?(k)) &&
                    !except.include?(k)
          if descend
            flatten_into(out, k, value, sep)
          else
            out[k] = value
          end
        end
      end

      # Recursively write the leaves of `value` under the dotted `prefix`. Bounded by
      # MAX_FLATTEN_DEPTH: at the cap the remaining subtree is written as-is rather
      # than descended, so a pathologically deep hash cannot exhaust the stack.
      def flatten_into(out, prefix, value, sep, depth = 0)
        if value.is_a?(Hash) && value.present? && depth < MAX_FLATTEN_DEPTH
          value.each do |k, v|
            flatten_into(out, "#{prefix}#{sep}#{k}", v, sep, depth + 1)
          end
        else
          # Leaf, empty hash, or depth cap reached -> terminal value at this path.
          out[prefix] = value
        end
      end

      # ---- unnest / explode -------------------------------------------------

      # Emit one record per element of the Array at "field". Hash elements merge
      # over the parent's OTHER fields; scalar elements land under "value". Records
      # without an Array at "field" pass through unchanged. Bounded by MAX_RECORDS.
      def op_unnest(step, rows)
        field = field_name(step["field"])
        return rows if field.nil?

        value_key = field_name(step["value_key"]) || "value"
        out = []
        capped = false

        rows.each do |record|
          # Every emit (passthrough OR exploded element) is gated by the cap so a
          # pathological array — or a long tail of passthrough records — cannot
          # exceed MAX_RECORDS.
          if would_overflow?(out, 1)
            capped = true
            break
          end

          unless record.is_a?(Hash)
            out << record
            next
          end

          elements = hash_fetch(record, field)
          unless elements.is_a?(Array)
            # Nothing to explode -> pass the record through unchanged.
            out << record
            next
          end

          rest = drop_keys(record, [field])
          elements.each do |element|
            if would_overflow?(out, 1)
              capped = true
              break
            end
            out << explode_element(rest, element, value_key)
          end
          break if capped
        end

        log_cap("unnest", rows.size) if capped
        out
      end

      def explode_element(rest, element, value_key)
        if element.is_a?(Hash)
          # Element fields win over the parent's carried-over fields.
          rest.merge(stringify_keys(element))
        else
          rest.merge(value_key => element)
        end
      end

      # ---- select / project -------------------------------------------------

      # Keep only "fields" (wins) or remove "drop". Missing config -> passthrough.
      def op_select(step, rows)
        keep = string_list(step["fields"])
        drop = string_list(step["drop"])

        if keep.any?
          map_records(rows) { |record| keep_keys(record, keep) }
        elsif drop.any?
          map_records(rows) { |record| drop_keys(record, drop) }
        else
          rows
        end
      end

      def keep_keys(record, keep)
        s = stringify_keys(record)
        keep.each_with_object({}) { |k, out| out[k] = s[k] if s.key?(k) }
      end

      def drop_keys(record, drop)
        return record unless record.is_a?(Hash)

        drop_set = Array(drop).map(&:to_s).to_set
        stringify_keys(record).reject { |k, _| drop_set.include?(k) }
      end

      # ---- rename -----------------------------------------------------------

      # Rename keys per the {from=>to} map; keys not in the map are untouched.
      def op_rename(step, rows)
        raw = step["map"]
        return rows unless raw.is_a?(Hash) && raw.present?

        map = raw.each_with_object({}) { |(from, to), h| h[from.to_s] = to.to_s }
        map_records(rows) do |record|
          stringify_keys(record).each_with_object({}) do |(k, v), out|
            out[map.fetch(k, k)] = v
          end
        end
      end

      # ---- computed (WHITELISTED interpreter) -------------------------------

      # Write a derived value to the "as" field using a whitelisted op over
      # EXISTING fields. NEVER evals/sends to arbitrary methods.
      def op_computed(step, rows)
        as = field_name(step["as"])
        return rows if as.nil?

        fn = computed_op_for(step)
        map_records(rows) do |record|
          s = stringify_keys(record)
          value = compute_value(fn, step, s)
          # A nil result (unknown op / not computable) is still written so the
          # field's presence is deterministic; callers can select/drop it after.
          s.merge(as => value)
        end
      end

      # The inner computed op. When the step's "op" is the literal "computed"
      # (because a caller used a single "op" key for the step kind), fall back to
      # "fn"/"operation"/"compute" for the actual operation token.
      def computed_op_for(step)
        token = step["op"]
        if token.to_s == "computed"
          token = step["fn"] || step["operation"] || step["compute"]
        end
        token.to_s.strip.downcase
      end

      # Dispatch the computed op through an EXPLICIT case — the security boundary.
      # No metaprogramming: an unrecognized op returns nil (skip), never executes.
      def compute_value(fn, step, record)
        case fn
        when "concat"               then compute_concat(step, record)
        when "coalesce"             then compute_coalesce(step, record)
        when *ARITHMETIC_OPS        then compute_arithmetic(fn, step, record)
        when "upcase"               then compute_string_op(step, record) { |v| v.upcase }
        when "downcase"             then compute_string_op(step, record) { |v| v.downcase }
        when "strip"                then compute_string_op(step, record) { |v| v.strip }
        when "substring", "slice"   then compute_substring(step, record)
        when "template", "format"   then compute_template(step, record)
        else
          Rails.logger.debug { "[DataSources::TransformService] skipping unknown computed op #{fn.inspect}" }
          nil
        end
      end

      def compute_concat(step, record)
        sep = step["separator"].nil? ? "" : step["separator"].to_s
        field_list(step).map { |f| stringify_scalar(record[f]) }.join(sep)
      end

      def compute_coalesce(step, record)
        field_list(step).each do |f|
          v = record[f]
          return v if present_value?(v)
        end
        nil
      end

      def compute_arithmetic(fn, step, record)
        a, b = arithmetic_operands(step, record)
        return nil if a.nil? || b.nil?

        result =
          case fn
          when "+" then a + b
          when "-" then a - b
          when "*" then a * b
          when "/" then b.zero? ? nil : (a / b)
          end
        # Drop non-finite Float results (Infinity / NaN from huge operands) so a
        # pathological payload cannot poison a computed field with Infinity.
        return nil if result.is_a?(Float) && !result.finite?

        result
      end

      # Operands come from "a"/"b" (field names) or the first two "fields". Each is
      # resolved against the record and coerced to a number; non-numeric -> nil.
      def arithmetic_operands(step, record)
        if step.key?("a") || step.key?("b")
          [numeric(record[field_name(step["a"])]), numeric(record[field_name(step["b"])])]
        else
          fields = field_list(step)
          [numeric(record[fields[0]]), numeric(record[fields[1]])]
        end
      end

      def compute_string_op(step, record)
        f = field_name(step["field"])
        return nil if f.nil?

        v = record[f]
        return nil unless v.is_a?(String)

        yield v
      end

      def compute_substring(step, record)
        f = field_name(step["field"])
        return nil if f.nil?

        v = record[f]
        return nil unless v.is_a?(String)

        start = integer_or_nil(step["start"]) || 0
        length = integer_or_nil(step["length"])
        length.nil? ? v[start..] : v[start, length]
      end

      # Interpolate "{field}" tokens with existing field values; unknown -> "".
      def compute_template(step, record)
        template = step["template"]
        return nil unless template.is_a?(String)

        template.gsub(/\{([^{}]+)\}/) { stringify_scalar(record[Regexp.last_match(1).to_s.strip]) }
      end

      # ---- shared helpers ---------------------------------------------------

      def field_list(step)
        string_list(step["fields"])
      end

      def map_records(rows)
        rows.map do |record|
          record.is_a?(Hash) ? yield(record) : record
        end
      end

      # Read a field from a record tolerating string OR symbol keys.
      def hash_fetch(record, key)
        return nil unless record.is_a?(Hash)

        if record.key?(key)
          record[key]
        elsif record.key?(key.to_sym)
          record[key.to_sym]
        end
      end

      def stringify_keys(record)
        return {} unless record.is_a?(Hash)

        record.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
      end

      def string_list(value)
        Array(value).map(&:to_s).reject(&:empty?)
      end

      def field_name(value)
        return nil if value.nil?

        s = value.to_s.strip
        s.empty? ? nil : s
      end

      def present_value?(value)
        return false if value.nil?
        return false if value.respond_to?(:empty?) && value.empty?

        true
      end

      def stringify_scalar(value)
        return "" if value.nil?

        value.is_a?(String) ? value : value.to_s
      end

      # Coerce a value to a Numeric for arithmetic, or nil when not numeric.
      def numeric(value)
        case value
        when Numeric then value
        when String
          Float(value)
        else
          nil
        end
      rescue ArgumentError, TypeError
        nil
      end

      def integer_or_nil(value)
        return nil if value.nil?

        Integer(value.to_s.strip)
      rescue ArgumentError, TypeError
        nil
      end

      def separator(step)
        sep = step["separator"]
        sep.nil? || sep.to_s.empty? ? DEFAULT_SEPARATOR : sep.to_s
      end

      def step_op(step)
        (step["op"] || step[:op]).to_s.strip.downcase
      end

      def would_overflow?(out, additional)
        out.size + additional > MAX_RECORDS
      end

      def log_cap(op, input_size)
        Rails.logger.warn(
          "[DataSources::TransformService] #{op} capped output at #{MAX_RECORDS} records " \
          "(input #{input_size} records); overflow dropped"
        )
      end

      # Normalize the top-level config to string keys; tolerate symbol-keyed input
      # and non-Hash garbage (-> {} == passthrough).
      def normalize_config(cfg)
        return {} unless cfg.is_a?(Hash) && cfg.present?

        cfg.respond_to?(:deep_stringify_keys) ? cfg.deep_stringify_keys : stringify(cfg)
      end

      def stringify(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
        when Array then obj.map { |e| stringify(e) }
        else obj
        end
      end
    end
  end
end
