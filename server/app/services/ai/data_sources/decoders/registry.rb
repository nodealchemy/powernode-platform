# frozen_string_literal: true

module Ai
  module DataSources
    module Decoders
      # Selects the appropriate decoder for a fetched response body.
      #
      # Mirrors the generic-fallback registry shape used elsewhere in the
      # codebase (see Ai::Providers::Sync::Generic): a small static map keyed by
      # canonical format token, with a generic fallback when the format is
      # unknown. JSON is the canonical fallback decoder because the overwhelming
      # majority of integrated sources speak JSON and an unknown body most often
      # turns out to be JSON-ish.
      #
      # Contract:
      #   Registry.for(format:, content_type:) => decoder instance
      #   decoder.decode(raw_body, endpoint:)  => Array<Hash> (canonical records)
      module Registry
        module_function

        # Canonical format -> decoder class. Decoders are stateless, so a fresh
        # instance per lookup is cheap and keeps them thread-safe.
        DECODERS = {
          FormatDetector::JSON_FORMAT   => Json,
          FormatDetector::NDJSON_FORMAT => Ndjson,
          FormatDetector::XML_FORMAT    => Xml,
          FormatDetector::RSS_FORMAT    => Xml,
          FormatDetector::ATOM_FORMAT   => Xml,
          FormatDetector::HTML_FORMAT   => Xml,
          FormatDetector::CSV_FORMAT    => Csv
        }.freeze

        # The decoder used when the format is unknown / unmapped. JSON because it
        # is the dominant on-the-wire format and degrades gracefully (returns an
        # empty record set rather than raising on non-JSON input).
        GENERIC_FALLBACK = Json

        # Picks a decoder by canonical format, falling back to a content-type
        # probe, then to the generic (JSON) decoder. Always returns a usable
        # decoder instance — never nil, never raises.
        def for(format: nil, content_type: nil)
          klass = lookup(format)
          klass ||= lookup_by_content_type(content_type)
          klass ||= GENERIC_FALLBACK
          klass.new
        end

        # Returns true when a non-fallback decoder is registered for the format —
        # lets callers distinguish "we recognised this" from "we guessed JSON".
        def known_format?(format)
          DECODERS.key?(normalize(format))
        end

        def lookup(format)
          DECODERS[normalize(format)]
        end

        def lookup_by_content_type(content_type)
          return nil if content_type.nil?

          mime, _charset = FormatDetector.parse_content_type(content_type)
          fmt = FormatDetector.format_from_mime(mime)
          DECODERS[fmt]
        end

        def normalize(format)
          format.to_s.strip.downcase
        end

        # Shared charset handling for every decoder. Centralised here (rather than
        # duplicated per decoder) so transcoding behaviour is uniform: strip BOM,
        # transcode the declared/detected charset to UTF-8, and scrub invalid
        # bytes so a few bad octets never abort decoding of an otherwise valid
        # document.
        module Charset
          module_function

          DEFAULT = "UTF-8"

          BOM_UTF8    = "\xEF\xBB\xBF".b
          BOM_UTF16LE = "\xFF\xFE".b
          BOM_UTF16BE = "\xFE\xFF".b

          # Transcodes an arbitrary response body to a valid UTF-8 String.
          #
          # charset:  explicit source charset (e.g. from the detector / header).
          #           When nil we sniff a BOM, else assume UTF-8.
          # Returns a UTF-8 String guaranteed to satisfy #valid_encoding?.
          def to_utf8(raw_body, charset: nil)
            bytes = raw_body.to_s.b
            source = charset_for(bytes, charset)
            stripped = strip_bom(bytes)

            decoded =
              begin
                stripped.dup.force_encoding(source)
                        .encode(DEFAULT, invalid: :replace, undef: :replace, replace: "")
              rescue EncodingError, ArgumentError
                # Unknown/unsupported encoding name — treat as binary UTF-8.
                stripped.encode(DEFAULT, "UTF-8", invalid: :replace, undef: :replace, replace: "")
              end

            decoded.valid_encoding? ? decoded : decoded.scrub("")
          end

          # Resolves the effective source charset: explicit arg wins, then BOM,
          # then UTF-8.
          def charset_for(bytes, charset)
            return normalize_name(charset) if charset && !charset.to_s.strip.empty?

            bom_charset(bytes) || DEFAULT
          end

          def normalize_name(charset)
            name = charset.to_s.strip.upcase
            # Common aliases Ruby accepts but providers spell loosely.
            case name
            when "UTF8"        then "UTF-8"
            when "LATIN1", "ISO8859-1", "ISO-8859-1" then "ISO-8859-1"
            else name
            end
          end

          def bom_charset(bytes)
            return "UTF-8"    if bytes.start_with?(BOM_UTF8)
            return "UTF-16LE" if bytes.start_with?(BOM_UTF16LE)
            return "UTF-16BE" if bytes.start_with?(BOM_UTF16BE)

            nil
          end

          def strip_bom(bytes)
            return bytes.byteslice(BOM_UTF8.bytesize..)    if bytes.start_with?(BOM_UTF8)
            return bytes.byteslice(BOM_UTF16LE.bytesize..) if bytes.start_with?(BOM_UTF16LE)
            return bytes.byteslice(BOM_UTF16BE.bytesize..) if bytes.start_with?(BOM_UTF16BE)

            bytes
          end
        end
      end
    end
  end
end
