# frozen_string_literal: true

require "time"
require "bigdecimal"

module Ai
  module DataSources
    # Normalizes decoded data-source records into a canonical form and emits a
    # provenance log describing every value-level conversion applied.
    #
    # Three normalization families are supported:
    #   - Dates/times  → coerced to UTC ISO-8601 (RFC 3339) strings.
    #   - Strings      → Unicode NFC (canonical composition).
    #   - Currency     → ISO-4217 validation + canonical major-unit decimal,
    #                    via the money-rails / money gem.
    #
    # Usage:
    #   normalized, provenance = NormalizationService.new(rules).apply(records)
    #
    # `rules` (Hash, indifferent-ish keys accepted) declares per-field handling.
    # When a field is not declared, value-shape heuristics still apply for dates
    # and strings so the service is useful with sparse or empty rules.
    #
    #   {
    #     "dates"    => { "fields" => ["observed_at", "published"], "assume_zone" => "UTC" },
    #     "currency" => {
    #       "fields" => {
    #         "price"  => { "currency_field" => "ccy" },   # currency from sibling field
    #         "fee"    => { "currency" => "USD" }          # fixed currency
    #       }
    #     },
    #     "strings"  => { "normalize_all" => true, "exclude" => ["raw_blob"] },
    #     "infer_dates" => true   # default true: ISO-ish strings auto-coerced
    #   }
    #
    # Provenance is an Array of Hashes, one per applied conversion:
    #   { record_index:, field:, type: "date"|"unicode_nfc"|"currency",
    #     from:, to:, currency:, note: }
    # `from` values that look like secrets are NOT included verbatim for
    # currency/date (they are structural values), but raw originals are kept so
    # downstream auditing can diff — callers redact at the log boundary.
    class NormalizationService
      class NormalizationError < StandardError; end

      # Strings matching this are treated as date/datetime candidates for
      # inference when no explicit date-field rule is present. Deliberately
      # conservative: must start with YYYY-MM-DD or YYYY/MM/DD.
      ISO_DATEISH = /\A\d{4}[-\/]\d{2}[-\/]\d{2}([ T]\d{2}:\d{2})?/

      def initialize(rules = {})
        @rules = normalize_rules(rules)
      end

      # Apply normalization to a collection of canonical records.
      #
      # @param records [Array<Hash>] decoded records (string or symbol keys)
      # @return [Array(Array<Hash>, Array<Hash>)] [normalized_records, provenance]
      def apply(records)
        provenance = []
        return [[], provenance] if records.blank?

        normalized = Array(records).each_with_index.map do |record, index|
          unless record.is_a?(Hash)
            # Non-hash records pass through untouched but are noted.
            provenance << provenance_entry(index, nil, "skipped", from: record.class.name, to: nil,
                                                                   note: "record is not a Hash; left unchanged")
            next record
          end

          normalize_record(record, index, provenance)
        end

        [normalized, provenance]
      end

      private

      # ---- per-record ---------------------------------------------------------

      def normalize_record(record, index, provenance)
        # Expose the in-progress record so currency rules can read a sibling
        # currency field (e.g. price + ccy). Cleared after the record.
        @current_record = record
        out = {}
        record.each do |key, value|
          field = key.to_s
          out[key] = normalize_value(field, value, index, provenance)
        end
        out
      ensure
        @current_record = nil
      end

      def normalize_value(field, value, index, provenance)
        # Currency takes precedence: an explicit currency rule turns a numeric
        # value into a canonical {amount, currency} pair.
        if (ccy_rule = currency_rule_for(field))
          return normalize_currency(field, value, ccy_rule, index, provenance)
        end

        case value
        when String
          normalize_string(field, value, index, provenance)
        when Time, DateTime, Date
          normalize_temporal(field, value, index, provenance)
        when Hash
          # Recurse into nested hashes (e.g. GeoJSON properties).
          value.each_with_object({}) do |(k, v), acc|
            acc[k] = normalize_value("#{field}.#{k}", v, index, provenance)
          end
        when Array
          value.map { |el| normalize_value(field, el, index, provenance) }
        else
          value
        end
      end

      # ---- strings + dates ----------------------------------------------------

      def normalize_string(field, value, index, provenance)
        # Explicitly date-typed field, or an opt-in inferred ISO-ish string →
        # coerce to UTC ISO-8601.
        if date_field?(field) || (infer_dates? && value.match?(ISO_DATEISH))
          coerced = coerce_date_string(field, value, index, provenance)
          return coerced unless coerced.nil?
        end

        return value unless string_normalizable?(field)

        nfc = value.unicode_normalize(:nfc)
        if nfc != value
          provenance << provenance_entry(index, field, "unicode_nfc",
                                         from: value, to: nfc,
                                         note: "Unicode normalized to NFC")
        end
        nfc
      end

      def normalize_temporal(field, value, index, provenance)
        # Capture the original rendering BEFORE conversion. to_utc_iso8601 must
        # not mutate `value`, and we record the value's own (offset-preserving)
        # form so the provenance "from" reflects the true input. Coercing a
        # Time/Date/DateTime OBJECT into a canonical ISO-8601 string is always a
        # value-level conversion (object -> normalized string), so provenance is
        # emitted unconditionally here — even when the wall-clock coincides with
        # UTC — per the "record every conversion" contract.
        original = value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
        utc_iso = to_utc_iso8601(value)
        provenance << provenance_entry(index, field, "date",
                                       from: original, to: utc_iso,
                                       note: "coerced to UTC ISO-8601")
        utc_iso
      end

      def coerce_date_string(field, value, index, provenance)
        parsed = parse_temporal(value)
        return nil if parsed.nil?

        utc_iso = to_utc_iso8601(parsed)
        if utc_iso != value
          provenance << provenance_entry(index, field, "date",
                                         from: value, to: utc_iso,
                                         note: "parsed and coerced to UTC ISO-8601")
        end
        utc_iso
      rescue ArgumentError, RangeError
        # Not actually a date despite matching the heuristic — leave as-is and
        # fall through to string handling by returning nil.
        nil
      end

      def parse_temporal(value)
        zone = @rules.dig("dates", "assume_zone")
        # If the string carries no explicit offset and a zone is configured,
        # interpret it in that zone before converting to UTC.
        if zone.present? && !value.match?(/[zZ]|[+\-]\d{2}:?\d{2}\z/)
          tz = ActiveSupport::TimeZone[zone]
          return tz.parse(value) if tz
        end
        Time.parse(value)
      rescue ArgumentError
        nil
      end

      def to_utc_iso8601(value)
        time =
          case value
          when Time then value
          when DateTime then value.to_time
          when Date then value.to_time(:utc)
          else Time.parse(value.to_s)
          end
        # getutc returns a NEW Time in UTC; Time#utc would mutate the receiver in
        # place, corrupting any later read of the original value (e.g. the
        # provenance "from" rendering and the caller's own object).
        time.getutc.iso8601
      end

      # ---- currency -----------------------------------------------------------

      def normalize_currency(field, value, ccy_rule, index, provenance)
        currency_code = resolve_currency_code(ccy_rule)
        currency = Money::Currency.find(currency_code) if currency_code
        unless currency
          provenance << provenance_entry(index, field, "currency",
                                         from: value, to: value, currency: currency_code,
                                         note: "currency #{currency_code.inspect} not ISO-4217; left unchanged")
          return value
        end

        amount = extract_amount(value)
        if amount.nil?
          provenance << provenance_entry(index, field, "currency",
                                         from: value, to: value, currency: currency.iso_code,
                                         note: "non-numeric amount; left unchanged")
          return value
        end

        money = Money.from_amount(amount, currency.iso_code)
        canonical = {
          "amount" => format_amount(money, currency),
          "currency" => currency.iso_code,
          "minor_units" => money.fractional.to_i
        }

        provenance << provenance_entry(index, field, "currency",
                                       from: value, to: canonical["amount"],
                                       currency: currency.iso_code,
                                       note: "normalized to ISO-4217 #{currency.iso_code} (#{currency.subunit_to_unit} minor units/major)")
        canonical
      end

      def resolve_currency_code(ccy_rule)
        # Fixed currency wins; otherwise read from the per-record sibling field
        # captured at record-normalization time.
        return ccy_rule[:fixed].to_s.upcase if ccy_rule[:fixed].present?

        ccy_rule[:resolved]&.to_s&.upcase
      end

      def extract_amount(value)
        case value
        when Numeric then BigDecimal(value.to_s)
        when String
          cleaned = value.gsub(/[^\d.\-]/, "")
          cleaned.empty? ? nil : BigDecimal(cleaned)
        when Hash
          raw = value["amount"] || value[:amount] || value["value"] || value[:value]
          raw.nil? ? nil : extract_amount(raw)
        end
      rescue ArgumentError
        nil
      end

      def format_amount(money, currency)
        # Major-unit decimal string with the currency's natural precision
        # (e.g. 2 for USD, 0 for JPY).
        decimals = Math.log10(currency.subunit_to_unit).round
        format("%.#{decimals}f", money.amount.to_f)
      end

      # ---- rule resolution ----------------------------------------------------

      # Currency rules need the sibling currency value resolved per-record. We
      # do a light pre-pass: for each field with a currency rule that references
      # a sibling field, this is resolved lazily through normalize_record's hash.
      #
      # To keep the single-pass design simple, currency_rule_for returns the
      # static rule and resolve happens against @current_record set per record.
      def currency_rule_for(field)
        spec = @rules.dig("currency", "fields", field)
        return nil unless spec

        if spec["currency"].present?
          { fixed: spec["currency"] }
        elsif spec["currency_field"].present?
          { resolved: @current_record&.[](spec["currency_field"]) ||
                      @current_record&.[](spec["currency_field"].to_sym) }
        else
          { fixed: Money.default_currency.iso_code }
        end
      end

      def date_field?(field)
        Array(@rules.dig("dates", "fields")).map(&:to_s).include?(field)
      end

      def string_normalizable?(field)
        strings = @rules["strings"] || {}
        excluded = Array(strings["exclude"]).map(&:to_s)
        return false if excluded.include?(field)

        # Default ON: NFC is safe and idempotent. Opt out with normalize_all:false.
        strings.key?("normalize_all") ? !!strings["normalize_all"] : true
      end

      def infer_dates?
        @rules.key?("infer_dates") ? !!@rules["infer_dates"] : true
      end

      def normalize_rules(rules)
        return {} if rules.blank?

        rules.respond_to?(:deep_stringify_keys) ? rules.deep_stringify_keys : stringify(rules)
      end

      def stringify(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
        when Array then obj.map { |e| stringify(e) }
        else obj
        end
      end

      def provenance_entry(index, field, type, from:, to:, currency: nil, note: nil)
        {
          record_index: index,
          field: field,
          type: type,
          from: from,
          to: to,
          currency: currency,
          note: note
        }.compact
      end
    end
  end
end
