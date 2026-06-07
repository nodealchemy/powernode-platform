# frozen_string_literal: true

require "json"

module Ai
  module DataSources
    module Decoders
      # Decodes a JSON response body into an Array<Hash> of canonical records.
      #
      # Records are located via the endpoint's response_mapping:
      #   - "records_path"  => dotted path or JSON pointer to the array/object
      #                        holding the records (e.g. "data.items" or
      #                        "/data/items"). Numeric path segments index into
      #                        arrays.
      #   - when no records_path is given we infer:
      #       * a top-level Array            -> each element is a record
      #       * a top-level Hash             -> the single record (wrapped)
      #       * a top-level scalar           -> wrapped as { "value" => scalar }
      #
      # Non-Hash elements found where records are expected are wrapped as
      # { "value" => element } so the canonical contract (Array<Hash>) always
      # holds. Parse failures degrade to an empty record set (logged) rather
      # than raising — the QueryService records this as an anomaly.
      class Json
        VALUE_KEY = "value"

        def decode(raw_body, endpoint: nil)
          charset = charset_for(endpoint)
          text = Registry::Charset.to_utf8(raw_body, charset: charset)
          return [] if text.strip.empty?

          parsed = parse(text)
          return [] if parsed.nil?

          extract_records(parsed, endpoint)
        end

        private

        # Parses JSON, returning nil (and logging) on malformed input so callers
        # get a stable empty result rather than an exception.
        def parse(text)
          JSON.parse(text)
        rescue JSON::ParserError => e
          Rails.logger.warn("[Decoders::Json] parse failed: #{e.message}")
          nil
        end

        # Walks the configured records_path (if any) and normalises the located
        # value into Array<Hash>.
        def extract_records(parsed, endpoint)
          located = apply_records_path(parsed, records_path(endpoint))
          normalize_collection(located)
        end

        # Resolves a dotted path / JSON pointer against the parsed document.
        # Returns the located node, or the original document when no path is set.
        # Returns nil when the path does not resolve.
        def apply_records_path(node, path)
          return node if path.nil? || path.empty?

          segments(path).reduce(node) do |current, key|
            break nil if current.nil?

            fetch_segment(current, key)
          end
        end

        def fetch_segment(current, key)
          case current
          when Hash
            current[key] || current[key.to_s]
          when Array
            idx = Integer(key, exception: false)
            idx ? current[idx] : nil
          end
        end

        # Splits "data.items" or "/data/items" into ["data", "items"].
        def segments(path)
          str = path.to_s
          if str.start_with?("/")
            str.split("/").reject(&:empty?)
          else
            str.split(".").reject(&:empty?)
          end
        end

        # Coerces an arbitrary located node into Array<Hash>.
        def normalize_collection(node)
          case node
          when Array
            node.map { |el| wrap_record(el) }
          when Hash
            [node]
          when nil
            []
          else
            [{ VALUE_KEY => node }]
          end
        end

        def wrap_record(element)
          element.is_a?(Hash) ? element : { VALUE_KEY => element }
        end

        # response_mapping may carry the records path under a few common keys.
        def records_path(endpoint)
          mapping = response_mapping(endpoint)
          return nil unless mapping.is_a?(Hash)

          mapping["records_path"] || mapping["root"] || mapping["data_path"] ||
            mapping[:records_path]
        end

        def response_mapping(endpoint)
          return {} unless endpoint.respond_to?(:response_mapping)

          endpoint.response_mapping || {}
        end

        def charset_for(endpoint)
          mapping = response_mapping(endpoint)
          mapping.is_a?(Hash) ? (mapping["charset"] || mapping[:charset]) : nil
        end
      end
    end
  end
end
