# frozen_string_literal: true

module SupplyChain
  module Generators
    class BaseGenerator
      class GeneratorError < StandardError; end

      attr_reader :account, :source_path, :options

      def initialize(account:, source_path:, options: {})
        @account = account
        @source_path = source_path
        @options = options.with_indifferent_access
        @logger = Rails.logger
      end

      def generate
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      def parse_lockfile(content)
        raise NotImplementedError, "#{self.class} must implement #parse_lockfile"
      end

      protected

      def ecosystem
        raise NotImplementedError, "#{self.class} must implement #ecosystem"
      end

      def build_purl(name:, version:, namespace: nil)
        purl = "pkg:#{ecosystem}/"
        purl += "#{namespace}/" if namespace.present?
        purl += name
        purl += "@#{version}" if version.present?
        purl
      end

      def build_component(name:, version:, purl: nil, **attrs)
        {
          name: name,
          version: version,
          purl: purl || build_purl(name: name, version: version, namespace: attrs[:namespace]),
          ecosystem: ecosystem,
          dependency_type: attrs[:dependency_type] || "direct",
          depth: attrs[:depth] || 0,
          license_spdx_id: attrs[:license_spdx_id],
          license_name: attrs[:license_name],
          namespace: attrs[:namespace]
        }
      end

      def read_file(relative_path)
        return nil unless source_path.present?

        full_path = File.join(source_path, relative_path)
        return nil unless File.exist?(full_path)

        File.read(full_path)
      end

      def parse_json(content)
        JSON.parse(content)
      rescue JSON::ParserError => e
        @logger.error "[#{self.class.name}] JSON parse error: #{e.message}"
        nil
      end

      def fetch_package_info(name, version = nil)
        # Placeholder for fetching package metadata from registries
        nil
      end

      def detect_license_from_text(text)
        # Simple license detection
        return nil unless text.present?

        text = text.downcase
        case text
        when /mit/i then "MIT"
        when /apache.*2/i then "Apache-2.0"
        when /bsd.*3/i then "BSD-3-Clause"
        when /bsd.*2/i then "BSD-2-Clause"
        when /gpl.*3/i then "GPL-3.0-only"
        when /gpl.*2/i then "GPL-2.0-only"
        when /lgpl.*3/i then "LGPL-3.0-only"
        when /lgpl.*2/i then "LGPL-2.1-only"
        when /mpl.*2/i then "MPL-2.0"
        when /isc/i then "ISC"
        when /unlicense/i then "Unlicense"
        end
      end

      def log_info(message)
        @logger.info "[#{self.class.name}] #{message}"
      end

      def log_warn(message)
        @logger.warn "[#{self.class.name}] #{message}"
      end

      def log_error(message)
        @logger.error "[#{self.class.name}] #{message}"
      end
    end
  end
end
