# frozen_string_literal: true

require "json"

module Ai
  module DataSources
    module Decoders
      # Decodes a newline-delimited JSON (NDJSON / JSON Lines) body into an
      # Array<Hash> of canonical records — one parsed value per non-blank line.
      #
      # Robustness rules:
      #   - Blank / whitespace-only lines are skipped.
      #   - A single malformed line is logged and skipped; the rest of the
      #     stream still decodes (NDJSON's whole point is line independence).
      #   - Non-Hash line values (scalars, arrays) are wrapped as
      #     { "value" => parsed } so the canonical Array<Hash> contract holds.
      #   - Handles \n, \r\n and \r line endings.
      class Ndjson
        VALUE_KEY = "value"

        # Cap on malformed lines we log individually before going quiet, so a
        # totally-wrong payload (e.g. a JSON array fed as NDJSON) doesn't flood
        # the log with one warning per line.
        MAX_LOGGED_ERRORS = 5

        def decode(raw_body, endpoint: nil)
          charset = charset_for(endpoint)
          text = Registry::Charset.to_utf8(raw_body, charset: charset)
          return [] if text.strip.empty?

          records = []
          error_count = 0

          each_line(text) do |line|
            stripped = line.strip
            next if stripped.empty?

            value = parse_line(stripped)
            if value.equal?(PARSE_FAILED)
              error_count += 1
              log_line_error(stripped, error_count)
              next
            end

            records << wrap_record(value)
          end

          if error_count > MAX_LOGGED_ERRORS
            Rails.logger.warn("[Decoders::Ndjson] suppressed #{error_count - MAX_LOGGED_ERRORS} additional parse errors")
          end

          records
        end

        private

        # Sentinel distinguishing a genuine `null` line from a parse failure.
        PARSE_FAILED = Object.new.freeze
        private_constant :PARSE_FAILED

        # Yields each logical line, normalising CRLF / CR to LF first.
        def each_line(text)
          text.gsub(/\r\n?/, "\n").each_line { |line| yield(line) }
        end

        def parse_line(stripped)
          JSON.parse(stripped)
        rescue JSON::ParserError
          PARSE_FAILED
        end

        def wrap_record(value)
          value.is_a?(Hash) ? value : { VALUE_KEY => value }
        end

        def log_line_error(stripped, error_count)
          return if error_count > MAX_LOGGED_ERRORS

          preview = stripped[0, 120]
          Rails.logger.warn("[Decoders::Ndjson] skipping malformed line: #{preview}")
        end

        def charset_for(endpoint)
          return nil unless endpoint.respond_to?(:response_mapping)

          mapping = endpoint.response_mapping || {}
          mapping.is_a?(Hash) ? (mapping["charset"] || mapping[:charset]) : nil
        end
      end
    end
  end
end
