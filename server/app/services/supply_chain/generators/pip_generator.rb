# frozen_string_literal: true

module SupplyChain
  module Generators
    class PipGenerator < BaseGenerator
      def generate
        components = []

        # Try different Python dependency files in order of preference
        if (content = read_file("Pipfile.lock"))
          components = parse_pipfile_lock(content)
        elsif (content = read_file("poetry.lock"))
          components = parse_poetry_lock(content)
        elsif (content = read_file("requirements.txt"))
          components = parse_requirements(content)
        end

        { components: components, vulnerabilities: [] }
      end

      def parse_lockfile(content)
        # Try to detect lockfile format
        if content.include?('"_meta"') && content.include?('"default"')
          { components: parse_pipfile_lock(content) }
        elsif content.include?("[[package]]")
          { components: parse_poetry_lock(content) }
        else
          { components: parse_requirements(content) }
        end
      end

      protected

      def ecosystem
        "pip"
      end

      private

      def parse_pipfile_lock(content)
        components = []

        begin
          lockfile = JSON.parse(content)

          %w[default develop].each do |section|
            deps = lockfile[section] || {}
            dep_type = section == "develop" ? "dev" : "direct"

            deps.each do |name, info|
              version = info["version"]&.gsub(/^==/, "")
              next unless version.present?

              components << build_component(
                name: name,
                version: version,
                purl: "pkg:pypi/#{normalize_pypi_name(name)}@#{version}",
                dependency_type: dep_type,
                depth: 0
              )
            end
          end
        rescue JSON::ParserError => e
          log_error "Failed to parse Pipfile.lock: #{e.message}"
        end

        components
      end

      def parse_poetry_lock(content)
        components = []

        begin
          current_package = nil

          content.each_line do |line|
            line = line.chomp

            if line == "[[package]]"
              current_package = {}
            elsif current_package && line =~ /^name\s*=\s*"(.+)"$/
              current_package[:name] = $1
            elsif current_package && line =~ /^version\s*=\s*"(.+)"$/
              current_package[:version] = $1
            elsif current_package && line =~ /^category\s*=\s*"(.+)"$/
              current_package[:category] = $1
            elsif line.empty? && current_package && current_package[:name] && current_package[:version]
              dep_type = current_package[:category] == "dev" ? "dev" : "direct"

              components << build_component(
                name: current_package[:name],
                version: current_package[:version],
                purl: "pkg:pypi/#{normalize_pypi_name(current_package[:name])}@#{current_package[:version]}",
                dependency_type: dep_type,
                depth: 0
              )

              current_package = nil
            end
          end

          # Handle last package if file doesn't end with empty line
          if current_package && current_package[:name] && current_package[:version]
            dep_type = current_package[:category] == "dev" ? "dev" : "direct"
            components << build_component(
              name: current_package[:name],
              version: current_package[:version],
              purl: "pkg:pypi/#{normalize_pypi_name(current_package[:name])}@#{current_package[:version]}",
              dependency_type: dep_type,
              depth: 0
            )
          end
        rescue StandardError => e
          log_error "Failed to parse poetry.lock: #{e.message}"
        end

        components
      end

      def parse_requirements(content)
        components = []

        content.each_line do |line|
          line = line.strip

          # Skip comments and empty lines
          next if line.empty? || line.start_with?("#")
          # Skip options like --index-url
          next if line.start_with?("-")

          # Parse package specifications
          # name==version, name>=version, name~=version, name[extras]==version
          if line =~ /^([a-zA-Z0-9_.-]+)(?:\[[^\]]+\])?\s*(==|>=|<=|~=|!=|>|<)?\s*([0-9][a-zA-Z0-9._-]*)?/
            name = $1
            version = $3 || "unknown"

            components << build_component(
              name: name,
              version: version,
              purl: "pkg:pypi/#{normalize_pypi_name(name)}@#{version}",
              dependency_type: "direct",
              depth: 0
            )
          end
        end

        components
      end

      def normalize_pypi_name(name)
        # PyPI names are case-insensitive and treat hyphens and underscores as equivalent
        name.downcase.gsub(/[-_.]+/, "-")
      end
    end
  end
end
