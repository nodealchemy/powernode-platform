# frozen_string_literal: true

module SupplyChain
  module Generators
    class NpmGenerator < BaseGenerator
      LOCKFILE_NAMES = %w[package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml].freeze

      def generate
        manifest = read_manifest
        lockfile_content = read_lockfile

        components = []

        if lockfile_content.present?
          components = parse_lockfile(lockfile_content)[:components]
        elsif manifest.present?
          components = parse_manifest(manifest)
        end

        { components: components, vulnerabilities: [] }
      end

      def parse_lockfile(content)
        components = []

        begin
          lockfile = JSON.parse(content)

          # Handle npm v2/v3 lockfile format
          packages = lockfile["packages"] || {}
          dependencies = lockfile["dependencies"] || {}

          if packages.any?
            # npm v2/v3 format with "packages" key
            packages.each do |path, pkg|
              next if path.empty? # Skip root package
              next if pkg["link"] # Skip linked packages

              name = extract_package_name(path)
              version = pkg["version"]
              next unless name.present? && version.present?

              components << build_component(
                name: name,
                version: version,
                purl: build_npm_purl(name, version),
                dependency_type: pkg["dev"] ? "dev" : "direct",
                depth: path.count("/"),
                license_spdx_id: normalize_license(pkg["license"])
              )
            end
          elsif dependencies.any?
            # npm v1 format with "dependencies" key
            parse_dependencies_v1(dependencies, components, 0)
          end
        rescue JSON::ParserError => e
          log_error "Failed to parse lockfile: #{e.message}"
        end

        { components: components }
      end

      protected

      def ecosystem
        "npm"
      end

      private

      def read_manifest
        content = read_file("package.json")
        return nil unless content

        parse_json(content)
      end

      def read_lockfile
        LOCKFILE_NAMES.each do |filename|
          content = read_file(filename)
          return content if content.present?
        end
        nil
      end

      def parse_manifest(manifest)
        components = []

        %w[dependencies devDependencies peerDependencies optionalDependencies].each do |dep_type|
          deps = manifest[dep_type] || {}
          dependency_type = dep_type == "devDependencies" ? "dev" : "direct"

          deps.each do |name, version_spec|
            version = clean_version(version_spec)
            components << build_component(
              name: name,
              version: version,
              purl: build_npm_purl(name, version),
              dependency_type: dependency_type,
              depth: 0
            )
          end
        end

        components
      end

      def parse_dependencies_v1(dependencies, components, depth)
        dependencies.each do |name, info|
          version = info["version"]
          next unless version.present?

          components << build_component(
            name: name,
            version: version,
            purl: build_npm_purl(name, version),
            dependency_type: info["dev"] ? "dev" : (depth == 0 ? "direct" : "transitive"),
            depth: depth
          )

          # Recursively parse nested dependencies
          if info["dependencies"].present?
            parse_dependencies_v1(info["dependencies"], components, depth + 1)
          end
        end
      end

      def extract_package_name(path)
        # path format: "node_modules/@scope/package" or "node_modules/package"
        parts = path.split("node_modules/").last
        return nil unless parts.present?

        parts.split("/node_modules/").last
      end

      def build_npm_purl(name, version)
        if name.include?("/")
          # Scoped package: @scope/name
          scope, pkg_name = name.split("/", 2)
          "pkg:npm/#{scope.delete('@')}/#{pkg_name}@#{version}"
        else
          "pkg:npm/#{name}@#{version}"
        end
      end

      def clean_version(version_spec)
        # Remove semver operators like ^, ~, >=, etc.
        version_spec.to_s.gsub(/^[\^~>=<]+/, "").split(" ").first
      end

      def normalize_license(license)
        return nil unless license.present?

        if license.is_a?(Hash)
          license = license["type"]
        end

        license = license.to_s.strip

        # Map common license variations to SPDX identifiers
        license_map = {
          "MIT" => "MIT",
          "ISC" => "ISC",
          "Apache-2.0" => "Apache-2.0",
          "Apache 2.0" => "Apache-2.0",
          "BSD-2-Clause" => "BSD-2-Clause",
          "BSD-3-Clause" => "BSD-3-Clause",
          "GPL-3.0" => "GPL-3.0-only",
          "GPL-2.0" => "GPL-2.0-only",
          "LGPL-3.0" => "LGPL-3.0-only",
          "LGPL-2.1" => "LGPL-2.1-only",
          "MPL-2.0" => "MPL-2.0",
          "Unlicense" => "Unlicense",
          "CC0-1.0" => "CC0-1.0",
          "WTFPL" => "WTFPL"
        }

        license_map[license] || license
      end
    end
  end
end
