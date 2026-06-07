# frozen_string_literal: true

module Ai
  module DataSources
    module Adapters
      # RSS / Atom feed adapter (protocol tokens "rss" and "atom").
      #
      # Feeds are ordinary HTTP GETs, so the OUTBOUND request shape is exactly the
      # generic REST behavior — RssAdapter is a thin RestAdapter subclass and only
      # overrides response parsing. The win is on the INBOUND side: a raw RSS/Atom
      # document has wildly different element names per dialect (RSS <item> with
      # <pubDate>/<description>/<guid>/<link>; Atom <entry> with
      # <published>/<updated>/<summary>/<id>/<link href=...>), so consumers cannot
      # treat them uniformly.
      #
      # This adapter:
      #   1. delegates structural decoding to the existing XML decoder (which
      #      already auto-locates <item>/<entry> nodes and namespace-strips), then
      #   2. maps each raw feed-item Hash onto a CANONICAL record with stable keys:
      #
      #        title      — item/entry title (text)
      #        link       — RSS <link> text, or Atom <link href="..."> (alternate
      #                     rel preferred when multiple links are present)
      #        published  — first present of pubDate / published / updated / dc:date
      #        summary    — first present of description / summary / content
      #        guid       — RSS <guid> (text), or Atom <id>
      #        id         — alias of guid (kept for callers keying on "id")
      #
      #      The original decoded fields are preserved under "raw" so nothing is
      #      lost (e.g. <author>, <category>, media extensions remain queryable).
      #
      # An explicit response_mapping["record_node"] / ["record_xpath"] still flows
      # through to the XML decoder, so an operator can point at a non-standard item
      # element and STILL get canonical records out.
      #
      # The mapping is intentionally forgiving: any field the feed omits is simply
      # absent from the canonical record (never a fabricated nil), and a record that
      # the decoder produced as a non-Hash is passed through untouched.
      class RssAdapter < RestAdapter
        TEXT_KEY = Decoders::Xml::TEXT_KEY

        # Candidate source keys per canonical field, in priority order. The first
        # key that yields a non-blank value wins. Atom + RSS spellings are merged
        # (namespaces are already stripped by the decoder, so "dc:date" arrives as
        # "date").
        TITLE_KEYS     = %w[title].freeze
        PUBLISHED_KEYS = %w[pubDate published updated date dc:date].freeze
        SUMMARY_KEYS   = %w[description summary content content:encoded].freeze
        GUID_KEYS      = %w[guid id].freeze
        LINK_KEYS      = %w[link].freeze

        # GET-only feed parse: decode the XML structure, then map each feed item to
        # a canonical record. Inherits build_request from RestAdapter unchanged.
        #
        # @param raw_body [String]
        # @param endpoint [Ai::DataSourceEndpoint]
        # @return [Array<Hash>] canonical feed records
        def parse(raw_body, endpoint:)
          items = xml_decoder.decode(raw_body, endpoint: endpoint)
          return [] unless items.is_a?(Array)

          items.map { |item| map_feed_item(item) }.compact
        end

        private

        # Reuse the shared XML decoder for structural decoding (record-node
        # location, namespace stripping, node->hash). Stateless, so memoize one.
        def xml_decoder
          @xml_decoder ||= Decoders::Xml.new
        end

        # Map one raw decoded feed-item Hash onto the canonical record shape.
        # Non-Hash inputs (a stray text record) are returned verbatim so the
        # contract (records are passed through) holds even for odd feeds.
        def map_feed_item(item)
          return item unless item.is_a?(Hash)

          record = {}
          assign(record, "title", pick(item, TITLE_KEYS))
          assign(record, "link", extract_link(item))
          assign(record, "published", pick(item, PUBLISHED_KEYS))
          assign(record, "summary", pick(item, SUMMARY_KEYS))

          guid = pick(item, GUID_KEYS)
          assign(record, "guid", guid)
          assign(record, "id", guid)

          # Preserve the full decoded item so nothing is dropped from the mapping.
          record["raw"] = item
          record
        end

        # Only set a key when there is a meaningful value (avoid fabricating nils
        # for fields a feed omits).
        def assign(record, key, value)
          record[key] = value unless value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end

        # First non-blank value across candidate keys, flattened to a scalar String.
        def pick(item, keys)
          keys.each do |key|
            next unless item.key?(key)

            value = scalarize(item[key])
            return value if value.present?
          end
          nil
        end

        # Link extraction is dialect-specific:
        #   RSS  -> <link>http://...</link>            (scalar text)
        #   Atom -> <link href="http://..." rel="..."/> (attribute on one-or-many)
        # When several links exist, prefer rel="alternate" (the canonical permalink),
        # else the first href. Falls back to scalar text for RSS.
        def extract_link(item)
          raw = item["link"] || item[:link]
          return nil if raw.nil?

          case raw
          when String
            raw.strip.presence
          when Hash
            href_from(raw)
          when Array
            link_from_collection(raw)
          end
        end

        def link_from_collection(links)
          hashes = links.select { |l| l.is_a?(Hash) }
          alternate = hashes.find { |l| (l["@rel"] || l[:@rel]).to_s == "alternate" }
          chosen = alternate || hashes.first
          return href_from(chosen) if chosen

          # A list of plain string links (rare) — take the first non-blank.
          links.map { |l| scalarize(l) }.find(&:present?)
        end

        # Pull the href from an Atom <link> hash (decoder renders attributes as
        # "@href"), falling back to the element text for an RSS-style hash.
        def href_from(hash)
          return nil unless hash.is_a?(Hash)

          (hash["@href"] || hash[:@href] || hash[TEXT_KEY] || hash["#text"]).to_s.strip.presence
        end

        # Reduce a decoded value to a scalar String. The XML decoder may render a
        # leaf as a String, or as a Hash carrying text under "#text" (mixed content
        # / attributed element). Arrays take the first usable element.
        def scalarize(value)
          case value
          when String then value.strip
          when Hash   then (value[TEXT_KEY] || value["#text"]).to_s.strip
          when Array  then value.map { |v| scalarize(v) }.find(&:present?)
          when nil    then nil
          else value.to_s.strip
          end
        end
      end
    end
  end
end
