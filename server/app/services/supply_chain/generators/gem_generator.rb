# frozen_string_literal: true

module SupplyChain
  module Generators
    class GemGenerator < BaseGenerator
      def generate
        lockfile_content = read_file("Gemfile.lock")

        components = if lockfile_content.present?
                       parse_lockfile(lockfile_content)[:components]
                     else
                       parse_gemfile
                     end

        { components: components, vulnerabilities: [] }
      end

      def parse_lockfile(content)
        components = []
        dependencies = {}  # Track which gems depend on which

        begin
          in_gems = false
          in_specs = false
          current_gem = nil

          content.each_line do |line|
            line = line.chomp

            if line == "GEM"
              in_gems = true
              next
            elsif line.match?(/^[A-Z]+$/)
              in_gems = false
              in_specs = false
              next
            end

            next unless in_gems

            # Check for specs: section
            if line.strip == "specs:"
              in_specs = true
              next
            end

            next unless in_specs

            # Parse gem entries - only 4-space indent (actual gems)
            # Format: "    gem_name (version)"
            # Dependency lines have 6+ space indent and often have operators like "= 7.0.0"
            if line =~ /^    (\S+)\s+\(([^)]+)\)$/
              name = $1
              version = $2.split(",").first.strip

              # Skip platform-specific versions
              next if version.include?("-")

              current_gem = name

              components << build_component(
                name: name,
                version: version,
                purl: "pkg:gem/#{name}@#{version}",
                dependency_type: "direct",
                depth: 0
              )
            elsif line =~ /^      (\S+)\s/ && current_gem
              # Track dependencies for depth calculation (6+ space indent)
              dep_name = $1
              dependencies[dep_name] ||= []
              dependencies[dep_name] << current_gem
            end
          end

          # Mark transitive dependencies based on dependency graph
          components.each do |comp|
            if dependencies[comp[:name]].present?
              comp[:dependency_type] = "transitive"
              comp[:depth] = 1
            end
          end
        rescue StandardError => e
          log_error "Failed to parse Gemfile.lock: #{e.message}"
        end

        { components: components }
      end

      protected

      def ecosystem
        "gem"
      end

      private

      def parse_gemfile
        content = read_file("Gemfile")
        return [] unless content.present?

        components = []

        content.each_line do |line|
          line = line.strip

          # Skip comments and empty lines
          next if line.empty? || line.start_with?("#")

          # Match gem declarations
          # gem 'name', '~> version'
          # gem 'name', 'version'
          # gem "name"
          if line =~ /gem\s+['"]([^'"]+)['"]/
            name = $1

            # Extract version if present
            version = nil
            if line =~ /,\s*['"]([~><=\s\d.]+)['"]/
              version = clean_version($1)
            end

            # Check for group
            dep_type = "direct"
            if line.include?(":development") || line.include?("group: :development")
              dep_type = "dev"
            end

            components << build_component(
              name: name,
              version: version || "unknown",
              purl: "pkg:gem/#{name}#{version ? "@#{version}" : ""}",
              dependency_type: dep_type,
              depth: 0
            )
          end
        end

        components
      end

      def clean_version(version_spec)
        # Remove operators and get base version
        version_spec.gsub(/[~><= ]/, "").strip
      end
    end
  end
end
