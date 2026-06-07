# frozen_string_literal: true

module Ai
  module DataSources
    module Decoders
      # Sniffs the on-the-wire format of a fetched response body so the right
      # decoder can be selected, independent of (and cross-checked against) the
      # provider's declared Content-Type.
      #
      # Detection precedence (highest-confidence signal first):
      #   1. Magic-byte / structural sniff of the raw body (BOM, leading token)
      #   2. XML root probe (`<?xml` prolog or a leading `<element>`)
      #   3. Declared Content-Type header (provider's claim)
      #   4. endpoint.expected_content_type (operator-configured expectation)
      #   5. application/octet-stream fallback (unknown -> generic/JSON decoder)
      #
      # The detector also flags a `mismatch` when the format implied by the
      # declared Content-Type disagrees with what the bytes actually look like
      # (e.g. a provider that returns an HTML error page with a JSON
      # Content-Type). Downstream the QueryService surfaces this as an anomaly.
      #
      # Contract:
      #   FormatDetector.detect(raw_body, declared_content_type:, endpoint:)
      #     => { format:, content_type:, mismatch:, charset:, declared_format:,
      #          detected_format:, source: }
      module FormatDetector
        module_function

        # Canonical format tokens shared with Registry. Values must line up with
        # Ai::DataSourceEndpoint::RESPONSE_FORMATS where they overlap.
        JSON_FORMAT    = "json"
        NDJSON_FORMAT  = "ndjson"
        XML_FORMAT     = "xml"
        CSV_FORMAT     = "csv"
        RSS_FORMAT     = "rss"
        ATOM_FORMAT    = "atom"
        HTML_FORMAT    = "html"
        TEXT_FORMAT    = "text"
        BINARY_FORMAT  = "binary"
        UNKNOWN_FORMAT = "unknown"

        OCTET_STREAM = "application/octet-stream"
        DEFAULT_CHARSET = "UTF-8"

        # How many leading bytes we are willing to inspect when sniffing. Keeps
        # detection O(1) on multi-megabyte payloads.
        SNIFF_WINDOW = 4096

        # Byte-order marks we strip / use as charset hints.
        BOM_UTF8    = "\xEF\xBB\xBF".b
        BOM_UTF16LE = "\xFF\xFE".b
        BOM_UTF16BE = "\xFE\xFF".b

        # Maps a parsed MIME type (no parameters) to a canonical format token.
        # Order-independent exact lookups; suffix handling (+json/+xml) done in
        # #format_from_mime.
        MIME_FORMAT_MAP = {
          "application/json"        => JSON_FORMAT,
          "text/json"               => JSON_FORMAT,
          "application/x-ndjson"    => NDJSON_FORMAT,
          "application/ndjson"      => NDJSON_FORMAT,
          "application/jsonl"       => NDJSON_FORMAT,
          "application/x-jsonlines" => NDJSON_FORMAT,
          "application/xml"         => XML_FORMAT,
          "text/xml"                => XML_FORMAT,
          "application/rss+xml"     => RSS_FORMAT,
          "application/atom+xml"    => ATOM_FORMAT,
          "text/csv"                => CSV_FORMAT,
          "application/csv"         => CSV_FORMAT,
          "text/tab-separated-values" => CSV_FORMAT,
          "text/html"               => HTML_FORMAT,
          "application/xhtml+xml"   => HTML_FORMAT,
          "text/plain"              => TEXT_FORMAT
        }.freeze

        # Primary entry point. Always returns a Hash (never raises) so callers can
        # rely on a stable envelope shape even for empty or garbage bodies.
        def detect(raw_body, declared_content_type: nil, endpoint: nil)
          body = raw_body.to_s
          window = body.byteslice(0, SNIFF_WINDOW).to_s.dup

          declared_mime, declared_charset = parse_content_type(declared_content_type)
          declared_format = format_from_mime(declared_mime)

          expected_mime, _expected_charset = parse_content_type(endpoint_expected(endpoint))
          expected_format = format_from_mime(expected_mime)

          sniffed = sniff_body(window)
          detected_format = sniffed[:format]

          # Charset precedence: BOM in the body > declared header charset > UTF-8.
          charset = sniffed[:charset] || declared_charset || DEFAULT_CHARSET

          chosen, source, content_type =
            choose_format(
              detected_format: detected_format,
              declared_format: declared_format,
              declared_mime: declared_mime,
              expected_format: expected_format,
              expected_mime: expected_mime
            )

          mismatch = format_mismatch?(detected_format, declared_format)

          {
            format: chosen,
            content_type: content_type,
            mismatch: mismatch,
            charset: charset,
            declared_format: declared_format,
            detected_format: (detected_format unless detected_format == UNKNOWN_FORMAT),
            source: source
          }
        end

        # --- format resolution ---------------------------------------------------

        # Applies the documented precedence to land on a single format token.
        # Returns [format, source_symbol, content_type_string].
        def choose_format(detected_format:, declared_format:, declared_mime:,
                          expected_format:, expected_mime:)
          if detected_format && detected_format != UNKNOWN_FORMAT
            [detected_format, :sniff, declared_mime || mime_for_format(detected_format)]
          elsif declared_format
            [declared_format, :declared_content_type, declared_mime]
          elsif expected_format
            [expected_format, :endpoint_expected, expected_mime]
          else
            [UNKNOWN_FORMAT, :octet_stream_fallback, OCTET_STREAM]
          end
        end

        # A mismatch is only meaningful when BOTH a confident byte-level format and
        # a declared format exist and they disagree. NDJSON vs JSON is treated as
        # compatible (NDJSON is a JSON superset framing); RSS/Atom vs XML and
        # HTML/XML overlaps are also tolerated.
        def format_mismatch?(detected_format, declared_format)
          return false if detected_format.nil? || detected_format == UNKNOWN_FORMAT
          return false if declared_format.nil?
          return false if detected_format == declared_format

          !compatible_formats?(detected_format, declared_format)
        end

        COMPATIBLE_FORMAT_GROUPS = [
          [JSON_FORMAT, NDJSON_FORMAT].freeze,
          [XML_FORMAT, RSS_FORMAT, ATOM_FORMAT, HTML_FORMAT].freeze
        ].freeze

        def compatible_formats?(a, b)
          COMPATIBLE_FORMAT_GROUPS.any? { |group| group.include?(a) && group.include?(b) }
        end

        # --- byte / structural sniffing -----------------------------------------

        # Inspects the leading window and returns { format:, charset: }. Never
        # raises; unknown bodies come back as UNKNOWN_FORMAT.
        def sniff_body(window)
          return { format: UNKNOWN_FORMAT, charset: nil } if window.nil? || window.empty?

          charset = bom_charset(window)
          stripped = strip_bom(window)

          # Decode the sniff window to a logical string for token inspection.
          probe = transcode_for_probe(stripped, charset)
          trimmed = probe.sub(/\A[\s\u{FEFF}]+/, "")

          return { format: UNKNOWN_FORMAT, charset: charset } if trimmed.empty?

          format =
            if xml_like?(trimmed)
              xml_subformat(trimmed)
            elsif json_object_or_array?(trimmed)
              json_or_ndjson(probe, trimmed)
            elsif ndjson_like?(probe)
              NDJSON_FORMAT
            elsif binary_like?(stripped)
              BINARY_FORMAT
            else
              UNKNOWN_FORMAT
            end

          { format: format, charset: charset }
        end

        # `<?xml ...`, `<!DOCTYPE`, `<!--`, or a bare opening element/tag.
        def xml_like?(trimmed)
          return true if trimmed.start_with?("<?xml", "<!DOCTYPE", "<!doctype", "<!--")
          # A leading `<` followed by a name-start char (letter or `/`) — element.
          trimmed.match?(/\A<\s*[A-Za-z\/!?]/)
        end

        # Distinguishes RSS / Atom / HTML / generic XML by the root element name.
        def xml_subformat(trimmed)
          # Skip prolog / comments / doctype to find the first real element name.
          scan = trimmed.dup
          scan = scan.sub(/\A<\?xml.*?\?>/m, "")
          scan = scan.sub(/\A\s*<!--.*?-->/m, "")
          scan = scan.sub(/\A\s*<!DOCTYPE[^>]*>/mi, "")
          scan = scan.sub(/\A[\s\u{FEFF}]+/, "")

          root = scan[/\A<\s*([A-Za-z_][\w:.\-]*)/, 1]&.downcase

          case root
          when "rss", "rdf", "rdf:rdf" then RSS_FORMAT
          when "feed"                  then ATOM_FORMAT
          when "html"                  then HTML_FORMAT
          else
            HTML_FORMAT_TAGS.include?(root) ? HTML_FORMAT : XML_FORMAT
          end
        end

        HTML_FORMAT_TAGS = %w[html body head].freeze

        def json_object_or_array?(trimmed)
          trimmed.start_with?("{", "[")
        end

        # A body that starts with `{`/`[` is JSON; but multiple top-level objects
        # separated by newlines is NDJSON. We treat a leading `{` followed by a
        # newline-delimited second `{` (with no enclosing array) as NDJSON.
        def json_or_ndjson(full_probe, trimmed)
          return JSON_FORMAT if trimmed.start_with?("[")

          # Count non-blank lines that each independently start with `{`.
          object_lines = full_probe.each_line.count do |line|
            line.lstrip.start_with?("{")
          end
          object_lines > 1 ? NDJSON_FORMAT : JSON_FORMAT
        end

        # Newline-delimited JSON where the first token is a JSON scalar/array/obj
        # repeated per line. Conservative: require at least two parseable lines.
        def ndjson_like?(full_probe)
          lines = full_probe.each_line.map(&:strip).reject(&:empty?).first(5)
          return false if lines.size < 2

          parseable = lines.count do |line|
            line.start_with?("{", "[") && safe_json?(line)
          end
          parseable >= 2
        end

        # Heuristic: a high proportion of NUL / non-text control bytes in the
        # leading window implies a binary payload.
        def binary_like?(stripped)
          bytes = stripped.b
          return false if bytes.empty?

          sample = bytes.byteslice(0, 512).to_s
          return true if sample.include?("\x00")

          control = sample.each_byte.count do |b|
            b < 0x09 || (b > 0x0D && b < 0x20)
          end
          control.to_f / sample.bytesize > 0.30
        end

        # --- content-type / charset parsing -------------------------------------

        # Splits "application/json; charset=utf-8" into ["application/json", "UTF-8"].
        # Returns [nil, nil] for blank input.
        def parse_content_type(content_type)
          return [nil, nil] if content_type.nil?

          str = content_type.to_s.strip
          return [nil, nil] if str.empty?

          parts = str.split(";")
          mime = parts.shift.to_s.strip.downcase
          mime = nil if mime.empty?

          charset = nil
          parts.each do |param|
            key, value = param.split("=", 2)
            next unless key && value
            next unless key.strip.casecmp("charset").zero?

            charset = value.strip.delete('"').upcase
            charset = nil if charset.empty?
          end

          [mime, charset]
        end

        # Resolves a MIME type to a canonical format token, honouring structured
        # suffixes (`+json`, `+xml`) for vendor media types.
        def format_from_mime(mime)
          return nil if mime.nil?

          return MIME_FORMAT_MAP[mime] if MIME_FORMAT_MAP.key?(mime)

          if mime.end_with?("+json")
            JSON_FORMAT
          elsif mime.end_with?("+xml")
            XML_FORMAT
          end
        end

        # Best-effort reverse mapping for synthesising a content_type when only a
        # sniffed format is known.
        def mime_for_format(format)
          {
            JSON_FORMAT   => "application/json",
            NDJSON_FORMAT => "application/x-ndjson",
            XML_FORMAT    => "application/xml",
            RSS_FORMAT    => "application/rss+xml",
            ATOM_FORMAT   => "application/atom+xml",
            CSV_FORMAT    => "text/csv",
            HTML_FORMAT   => "text/html",
            TEXT_FORMAT   => "text/plain"
          }.fetch(format, OCTET_STREAM)
        end

        # --- helpers ------------------------------------------------------------

        def endpoint_expected(endpoint)
          return nil unless endpoint.respond_to?(:expected_content_type)

          endpoint.expected_content_type
        end

        def bom_charset(window)
          bytes = window.b
          return "UTF-8"    if bytes.start_with?(BOM_UTF8)
          return "UTF-16LE" if bytes.start_with?(BOM_UTF16LE)
          return "UTF-16BE" if bytes.start_with?(BOM_UTF16BE)

          nil
        end

        def strip_bom(window)
          bytes = window.b
          return bytes.byteslice(BOM_UTF8.bytesize..)    if bytes.start_with?(BOM_UTF8)
          return bytes.byteslice(BOM_UTF16LE.bytesize..) if bytes.start_with?(BOM_UTF16LE)
          return bytes.byteslice(BOM_UTF16BE.bytesize..) if bytes.start_with?(BOM_UTF16BE)

          bytes
        end

        # Decodes the (already BOM-stripped) sniff window into a String we can run
        # token regexes against. Falls back to a scrubbed binary->UTF-8 view so a
        # few invalid bytes never abort detection.
        def transcode_for_probe(bytes, charset)
          source = charset && charset != "UTF-8" ? charset : "UTF-8"
          str = bytes.b.dup.force_encoding(source)
          if str.valid_encoding?
            str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          else
            bytes.b.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "")
          end
        rescue EncodingError
          bytes.b.scrub("")
        end

        def safe_json?(line)
          require "json"
          JSON.parse(line)
          true
        rescue JSON::ParserError, TypeError
          false
        end
      end
    end
  end
end
