# frozen_string_literal: true

require "csv"

module Ai
  module DataSources
    module Decoders
      # Decodes a delimited-text (CSV / TSV / semicolon / pipe) body into an
      # Array<Hash> of canonical records, one Hash per data row keyed by column
      # header.
      #
      # Dialect & header handling:
      #   - Delimiter is sniffed from the first non-empty line (comma, tab,
      #     semicolon, pipe) by picking the candidate with the most consistent
      #     field count across the sample — unless response_mapping pins one.
      #   - Headers are used when present. We sniff whether the first row looks
      #     like a header (non-numeric, unique tokens); when it doesn't, columns
      #     are named positionally ("column_1", "column_2", ...).
      #   - response_mapping overrides: "delimiter", "headers" (true/false/Array),
      #     "quote_char".
      #   - Malformed rows are skipped (logged) so one bad line never aborts the
      #     whole file; a wholly unparseable body degrades to an empty set.
      class Csv
        DEFAULT_DELIMITER = ","
        CANDIDATE_DELIMITERS = [",", "\t", ";", "|"].freeze
        DEFAULT_QUOTE = '"'
        POSITIONAL_PREFIX = "column_"

        # Lines sampled when sniffing the dialect / header.
        SNIFF_LINES = 20

        def decode(raw_body, endpoint: nil)
          mapping = response_mapping(endpoint)
          text = Registry::Charset.to_utf8(raw_body, charset: charset_for(mapping))
          # Normalise newlines so CSV's row splitting is predictable.
          text = text.gsub(/\r\n?/, "\n")
          return [] if text.strip.empty?

          delimiter = resolve_delimiter(text, mapping)
          quote_char = mapping["quote_char"] || mapping[:quote_char] || DEFAULT_QUOTE
          headers = resolve_headers(text, delimiter, quote_char, mapping)

          parse_rows(text, delimiter, quote_char, headers)
        end

        private

        # --- parsing ------------------------------------------------------------

        def parse_rows(text, delimiter, quote_char, headers)
          rows = []
          options = {
            col_sep: delimiter,
            quote_char: quote_char,
            skip_blanks: true,
            liberal_parsing: true,
            headers: headers,
            return_headers: false
          }

          begin
            CSV.parse(text, **options) do |row|
              record = row_to_hash(row, headers)
              rows << record if record
            end
          rescue CSV::MalformedCSVError => e
            Rails.logger.warn("[Decoders::Csv] malformed CSV, returning partial result: #{e.message}")
          end

          rows
        end

        # Converts a parsed CSV row into a canonical Hash. With header mode on,
        # CSV::Row already maps name->value; otherwise we name columns
        # positionally.
        def row_to_hash(row, headers)
          if row.is_a?(CSV::Row)
            hash = row.to_h
            return nil if hash.values.all? { |v| v.nil? || v.to_s.strip.empty? }

            hash.transform_keys { |k| k.nil? ? POSITIONAL_PREFIX : k.to_s }
          else
            cells = Array(row)
            return nil if cells.all? { |v| v.nil? || v.to_s.strip.empty? }

            positional_hash(cells)
          end
        end

        def positional_hash(cells)
          cells.each_with_index.each_with_object({}) do |(value, idx), acc|
            acc["#{POSITIONAL_PREFIX}#{idx + 1}"] = value
          end
        end

        # --- dialect sniffing ---------------------------------------------------

        # Honours an explicit delimiter, else sniffs the most consistent one.
        def resolve_delimiter(text, mapping)
          explicit = mapping["delimiter"] || mapping[:delimiter]
          return decode_escape(explicit) if explicit.present?

          sniff_delimiter(text)
        end

        # Picks the delimiter that yields the most uniform column count across the
        # sampled lines (and more than one column). Falls back to comma.
        def sniff_delimiter(text)
          lines = sample_lines(text)
          return DEFAULT_DELIMITER if lines.empty?

          scored = CANDIDATE_DELIMITERS.map do |delim|
            [delim, delimiter_score(lines, delim)]
          end

          best = scored.max_by { |(_delim, score)| score[:weight] }
          best && best[1][:weight].positive? ? best[0] : DEFAULT_DELIMITER
        end

        # Scores a delimiter by average field count and consistency. A delimiter
        # that splits every line into the same N>1 columns scores highest.
        def delimiter_score(lines, delim)
          counts = lines.map { |line| naive_field_count(line, delim) }
          counts.reject!(&:zero?)
          return { weight: 0, columns: 0 } if counts.empty?

          modal = counts.group_by(&:itself).max_by { |_k, v| v.size }.first
          consistency = counts.count(modal).to_f / counts.size
          columns = modal + 1 # field count -> column count

          weight = columns > 1 ? consistency * columns : 0
          { weight: weight, columns: columns }
        end

        # Rough field-separator count that ignores separators inside quotes.
        def naive_field_count(line, delim)
          in_quote = false
          count = 0
          line.each_char do |char|
            if char == DEFAULT_QUOTE
              in_quote = !in_quote
            elsif char == delim && !in_quote
              count += 1
            end
          end
          count
        end

        # --- header sniffing ----------------------------------------------------

        # Returns the value to hand CSV's `headers:` option:
        #   - an explicit Array of names, or
        #   - true  (use first row as headers), or
        #   - false (positional columns).
        def resolve_headers(text, delimiter, quote_char, mapping)
          explicit = mapping["headers"]
          explicit = mapping[:headers] if explicit.nil?

          case explicit
          when Array        then explicit.map(&:to_s)
          when true, false  then explicit
          else
            sniff_headers?(text, delimiter, quote_char)
          end
        end

        # Heuristic: the first row is a header when every field is non-empty,
        # mostly non-numeric, and all field names are unique.
        def sniff_headers?(text, delimiter, quote_char)
          first_two = parse_sample(text, delimiter, quote_char, 2)
          return false if first_two.empty?

          header_row = first_two.first
          return false if header_row.nil? || header_row.empty?

          non_blank = header_row.all? { |c| c && !c.to_s.strip.empty? }
          return false unless non_blank

          unique = header_row.map { |c| c.to_s.strip.downcase }.uniq.size == header_row.size
          mostly_text = header_row.count { |c| numeric?(c) }.to_f / header_row.size < 0.5

          # If a second row exists, a header is more believable when its types
          # differ from the first (e.g. header strings over numeric data).
          unique && mostly_text
        end

        def numeric?(value)
          str = value.to_s.strip
          return false if str.empty?

          !Float(str, exception: false).nil?
        end

        # --- helpers ------------------------------------------------------------

        def parse_sample(text, delimiter, quote_char, limit)
          rows = []
          CSV.parse(text, col_sep: delimiter, quote_char: quote_char,
                          skip_blanks: true, liberal_parsing: true) do |row|
            rows << row
            break if rows.size >= limit
          end
          rows
        rescue CSV::MalformedCSVError
          []
        end

        def sample_lines(text)
          text.each_line.lazy.map(&:chomp).reject(&:empty?).first(SNIFF_LINES) || []
        end

        # Allows "\t" to be specified as a literal escape in the mapping config.
        def decode_escape(value)
          str = value.to_s
          return "\t" if %w[\\t tab \t].include?(str)

          str
        end

        def response_mapping(endpoint)
          return {} unless endpoint.respond_to?(:response_mapping)

          mapping = endpoint.response_mapping
          mapping.is_a?(Hash) ? mapping : {}
        end

        def charset_for(mapping)
          mapping["charset"] || mapping[:charset]
        end
      end
    end
  end
end
