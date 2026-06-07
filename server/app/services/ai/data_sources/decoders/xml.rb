# frozen_string_literal: true

require "nokogiri"

module Ai
  module DataSources
    module Decoders
      # Decodes an XML / RSS / Atom / HTML body into an Array<Hash> of canonical
      # records using Nokogiri.
      #
      # Record location strategy:
      #   1. response_mapping["record_xpath"] — explicit XPath to record nodes.
      #   2. response_mapping["record_node"]  — element name; matched anywhere
      #                                         (namespace-agnostic).
      #   3. Auto-detection for well-known feed shapes:
      #        RSS / RDF -> <item> ; Atom -> <entry>
      #   4. Heuristic: the most-repeated sibling element under the document's
      #      primary container becomes the record node.
      #   5. Fallback: the whole document hashed as a single record.
      #
      # Each record node is converted to a Hash via a compact XML->Hash mapping
      # (attributes prefixed with "@", text under "#text" when an element has both
      # attributes/children and text, repeated children collected into arrays).
      class Xml
        TEXT_KEY = "#text"

        # Namespaces stripped before XPath so feeds with default namespaces (very
        # common in Atom) can be queried with plain element names.
        def decode(raw_body, endpoint: nil)
          charset = charset_for(endpoint)
          text = Registry::Charset.to_utf8(raw_body, charset: charset)
          return [] if text.strip.empty?

          doc = parse(text)
          return [] if doc.nil?

          doc.remove_namespaces!

          nodes = locate_record_nodes(doc, endpoint)
          return [hash_for(doc.root)].compact if nodes.empty? && doc.root

          nodes.map { |node| hash_for(node) }.compact
        end

        private

        # Parses XML, recovering from minor malformations (Nokogiri's default
        # recover mode). Returns nil and logs on catastrophic failure.
        def parse(text)
          doc = Nokogiri::XML(text) { |config| config.recover.nonet }
          # A doc with no root and parse errors is unusable.
          if doc.root.nil? && doc.errors.any?
            Rails.logger.warn("[Decoders::Xml] parse produced no root: #{doc.errors.first&.message}")
            return nil
          end

          doc
        rescue StandardError => e
          Rails.logger.warn("[Decoders::Xml] parse failed: #{e.message}")
          nil
        end

        # Resolves the set of record nodes per the strategy documented above.
        def locate_record_nodes(doc, endpoint)
          mapping = response_mapping(endpoint)

          if (xpath = mapping["record_xpath"] || mapping[:record_xpath]).present?
            return safe_xpath(doc, xpath)
          end

          if (node_name = mapping["record_node"] || mapping[:record_node]).present?
            return doc.xpath("//#{sanitize_name(node_name)}").to_a
          end

          feed_nodes = feed_record_nodes(doc)
          return feed_nodes unless feed_nodes.empty?

          heuristic_record_nodes(doc)
        end

        # Well-known feed element names (namespaces already removed).
        def feed_record_nodes(doc)
          %w[item entry].each do |name|
            found = doc.xpath("//#{name}").to_a
            return found unless found.empty?
          end
          []
        end

        # Picks the most frequently-repeated element name among the children of
        # the document's primary container, treating those siblings as records.
        def heuristic_record_nodes(doc)
          root = doc.root
          return [] if root.nil?

          container = primary_container(root)
          children = container.element_children.to_a
          return [] if children.empty?

          counts = children.group_by(&:name).transform_values(&:size)
          best_name, best_count = counts.max_by { |_name, count| count }

          # Only treat as a record collection when an element actually repeats.
          return [] if best_count.nil? || best_count < 2

          children.select { |c| c.name == best_name }
        end

        # Descends through single-child wrapper elements to find the element whose
        # children are the actual records (handles <response><results><row/>...).
        def primary_container(root)
          node = root
          loop do
            element_kids = node.element_children.to_a
            break if element_kids.size != 1

            node = element_kids.first
          end
          node
        end

        def safe_xpath(doc, xpath)
          doc.xpath(xpath).to_a
        rescue Nokogiri::XML::XPath::SyntaxError, StandardError => e
          Rails.logger.warn("[Decoders::Xml] invalid record_xpath '#{xpath}': #{e.message}")
          []
        end

        # --- node -> hash -------------------------------------------------------

        # Converts a single element node into a canonical Hash.
        def hash_for(node)
          return nil if node.nil?

          result = {}
          node.attribute_nodes.each do |attr|
            result["@#{attr.name}"] = attr.value
          end

          element_kids = node.element_children.to_a

          if element_kids.empty?
            text = node.text.to_s.strip
            return result.empty? ? text_record(text) : merge_text(result, text)
          end

          element_kids.each do |child|
            add_child(result, child)
          end

          # Preserve meaningful mixed-content text alongside child elements.
          own_text = node.xpath("./text()").map(&:text).join.strip
          result[TEXT_KEY] = own_text unless own_text.empty?

          result
        end

        # Adds a child element to the parent hash, collecting repeats into arrays.
        def add_child(result, child)
          key = child.name
          value = child_value(child)

          if result.key?(key)
            # Array.wrap (NOT Array()) — Array({"a"=>1}) explodes a hash into
            # [["a",1]] pairs, corrupting repeated element-with-attributes nodes
            # (e.g. two Atom <link rel=.. href=../>). Array.wrap keeps it [{...}].
            result[key] = Array.wrap(result[key]) << value
          else
            result[key] = value
          end
        end

        # A child is rendered as its scalar text when it is a leaf with no
        # attributes, otherwise as a nested Hash.
        def child_value(child)
          if child.element_children.empty? && child.attribute_nodes.empty?
            child.text.to_s.strip
          else
            hash_for(child)
          end
        end

        # A bare leaf element with only text becomes { "#text" => "..." } so the
        # canonical record is always a Hash.
        def text_record(text)
          { TEXT_KEY => text }
        end

        def merge_text(result, text)
          result[TEXT_KEY] = text unless text.empty?
          result
        end

        # --- config helpers -----------------------------------------------------

        # Restricts element names to a safe XPath name token to avoid injection
        # through a misconfigured record_node.
        def sanitize_name(name)
          name.to_s.gsub(/[^A-Za-z0-9_.\-:*]/, "")
        end

        def response_mapping(endpoint)
          return {} unless endpoint.respond_to?(:response_mapping)

          mapping = endpoint.response_mapping
          mapping.is_a?(Hash) ? mapping : {}
        end

        def charset_for(endpoint)
          mapping = response_mapping(endpoint)
          mapping["charset"] || mapping[:charset]
        end
      end
    end
  end
end
