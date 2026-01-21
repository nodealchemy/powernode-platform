# frozen_string_literal: true

module SupplyChain
  class SbomGenerationService
    class GenerationError < StandardError; end
    class UnsupportedEcosystemError < GenerationError; end

    ECOSYSTEM_GENERATORS = {
      "npm" => "SupplyChain::Generators::NpmGenerator",
      "gem" => "SupplyChain::Generators::GemGenerator",
      "pip" => "SupplyChain::Generators::PipGenerator",
      "maven" => "SupplyChain::Generators::MavenGenerator",
      "go" => "SupplyChain::Generators::GoGenerator",
      "cargo" => "SupplyChain::Generators::CargoGenerator"
    }.freeze

    SUPPORTED_FORMATS = %w[cyclonedx_1_5 cyclonedx_1_6 spdx_2_3].freeze

    attr_reader :account, :repository, :options

    def initialize(account:, repository: nil, options: {})
      @account = account
      @repository = repository
      @options = options.with_indifferent_access
      @logger = Rails.logger
    end

    def generate(source_path:, ecosystems: nil, format: "cyclonedx_1_5")
      validate_format!(format)

      detected_ecosystems = ecosystems || detect_ecosystems(source_path)
      raise GenerationError, "No supported ecosystems detected" if detected_ecosystems.empty?

      sbom = create_sbom_record(format)
      sbom.start_generation!

      begin
        all_components = []
        all_vulnerabilities = []

        detected_ecosystems.each do |ecosystem|
          generator = build_generator(ecosystem, source_path)
          result = generator.generate

          all_components.concat(result[:components] || [])
          all_vulnerabilities.concat(result[:vulnerabilities] || [])
        end

        document = build_document(format, all_components)
        persist_components(sbom, all_components)
        persist_vulnerabilities(sbom, all_vulnerabilities)

        sbom.complete_generation!(
          document,
          component_count: all_components.length,
          vuln_count: all_vulnerabilities.length
        )

        calculate_risk_score(sbom)
        sbom.verify_ntia_compliance

        sbom
      rescue StandardError => e
        sbom.fail_generation!(e.message)
        @logger.error "[SbomGenerationService] Generation failed: #{e.message}"
        raise GenerationError, "SBOM generation failed: #{e.message}"
      end
    end

    def generate_from_lockfiles(lockfiles:, format: "cyclonedx_1_5")
      validate_format!(format)

      sbom = create_sbom_record(format)
      sbom.start_generation!

      begin
        all_components = []

        lockfiles.each do |lockfile|
          ecosystem = detect_ecosystem_from_file(lockfile[:filename])
          next unless ecosystem

          generator = build_generator(ecosystem, nil)
          result = generator.parse_lockfile(lockfile[:content])

          all_components.concat(result[:components] || [])
        end

        document = build_document(format, all_components)
        persist_components(sbom, all_components)

        sbom.complete_generation!(document, component_count: all_components.length)
        sbom
      rescue StandardError => e
        sbom.fail_generation!(e.message)
        raise GenerationError, "SBOM generation failed: #{e.message}"
      end
    end

    def merge_sboms(sbom_ids:, format: nil)
      sboms = SupplyChain::Sbom.where(id: sbom_ids, account_id: account.id)
      raise GenerationError, "No SBOMs found to merge" if sboms.empty?

      target_format = format || sboms.first.format
      merged_sbom = create_sbom_record(target_format)

      all_components = {}
      sboms.each do |sbom|
        sbom.components.each do |component|
          key = component.purl
          if all_components[key].nil? || version_newer?(component.version, all_components[key][:version])
            all_components[key] = component.attributes.symbolize_keys
          end
        end
      end

      document = build_document(target_format, all_components.values)
      persist_components(merged_sbom, all_components.values)

      merged_sbom.complete_generation!(document, component_count: all_components.length)
      merged_sbom
    end

    private

    def validate_format!(format)
      unless SUPPORTED_FORMATS.include?(format)
        raise GenerationError, "Unsupported format: #{format}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
      end
    end

    def create_sbom_record(format)
      SupplyChain::Sbom.create!(
        account: account,
        repository: repository,
        format: format,
        status: "draft",
        created_by: options[:user],
        branch: options[:branch],
        commit_sha: options[:commit_sha],
        name: options[:name] || generate_sbom_name
      )
    end

    def generate_sbom_name
      parts = []
      parts << repository.name if repository
      parts << options[:branch] if options[:branch]
      parts << Time.current.strftime("%Y%m%d")
      parts.join("-")
    end

    def detect_ecosystems(source_path)
      ecosystems = []

      # Check for manifest files
      ecosystems << "npm" if File.exist?(File.join(source_path, "package.json"))
      ecosystems << "gem" if File.exist?(File.join(source_path, "Gemfile"))
      ecosystems << "pip" if File.exist?(File.join(source_path, "requirements.txt")) || File.exist?(File.join(source_path, "Pipfile"))
      ecosystems << "maven" if File.exist?(File.join(source_path, "pom.xml"))
      ecosystems << "go" if File.exist?(File.join(source_path, "go.mod"))
      ecosystems << "cargo" if File.exist?(File.join(source_path, "Cargo.toml"))

      ecosystems
    end

    def detect_ecosystem_from_file(filename)
      case filename.downcase
      when "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml"
        "npm"
      when "gemfile.lock"
        "gem"
      when "requirements.txt", "pipfile.lock", "poetry.lock"
        "pip"
      when "pom.xml", "gradle.lockfile"
        "maven"
      when "go.sum"
        "go"
      when "cargo.lock"
        "cargo"
      end
    end

    def build_generator(ecosystem, source_path)
      generator_class = ECOSYSTEM_GENERATORS[ecosystem]
      raise UnsupportedEcosystemError, "Unsupported ecosystem: #{ecosystem}" unless generator_class

      generator_class.constantize.new(
        account: account,
        source_path: source_path,
        options: options
      )
    end

    def build_document(format, components)
      case format
      when /cyclonedx/
        build_cyclonedx_document(format, components)
      when /spdx/
        build_spdx_document(format, components)
      else
        {}
      end
    end

    def build_cyclonedx_document(format, components)
      version = format.split("_").last.tr("_", ".")

      {
        "bomFormat" => "CycloneDX",
        "specVersion" => version,
        "serialNumber" => "urn:uuid:#{SecureRandom.uuid}",
        "version" => 1,
        "metadata" => {
          "timestamp" => Time.current.iso8601,
          "tools" => [
            {
              "vendor" => "Powernode",
              "name" => "Supply Chain Manager",
              "version" => "1.0.0"
            }
          ],
          "authors" => [
            { "name" => account.name }
          ],
          "component" => {
            "type" => "application",
            "name" => options[:name] || repository&.name || "Unknown",
            "version" => options[:version] || "1.0.0"
          }
        },
        "components" => components.map { |c| component_to_cyclonedx(c) },
        "dependencies" => build_dependency_graph(components)
      }
    end

    def build_spdx_document(format, components)
      {
        "spdxVersion" => "SPDX-2.3",
        "dataLicense" => "CC0-1.0",
        "SPDXID" => "SPDXRef-DOCUMENT",
        "name" => options[:name] || repository&.name || "Unknown",
        "documentNamespace" => "https://spdx.org/spdxdocs/#{SecureRandom.uuid}",
        "creationInfo" => {
          "created" => Time.current.iso8601,
          "creators" => ["Tool: Powernode-SupplyChainManager-1.0.0", "Organization: #{account.name}"]
        },
        "packages" => components.map { |c| component_to_spdx(c) },
        "relationships" => build_spdx_relationships(components)
      }
    end

    def component_to_cyclonedx(component)
      comp = component.is_a?(Hash) ? component : component.attributes
      {
        "type" => "library",
        "bom-ref" => comp[:purl] || comp["purl"],
        "name" => comp[:name] || comp["name"],
        "version" => comp[:version] || comp["version"],
        "purl" => comp[:purl] || comp["purl"],
        "licenses" => build_licenses(comp[:license_spdx_id] || comp["license_spdx_id"])
      }
    end

    def component_to_spdx(component)
      comp = component.is_a?(Hash) ? component : component.attributes
      {
        "SPDXID" => "SPDXRef-Package-#{Digest::SHA256.hexdigest(comp[:purl] || comp["purl"])[0..15]}",
        "name" => comp[:name] || comp["name"],
        "versionInfo" => comp[:version] || comp["version"],
        "downloadLocation" => "NOASSERTION",
        "licenseConcluded" => comp[:license_spdx_id] || comp["license_spdx_id"] || "NOASSERTION",
        "licenseDeclared" => comp[:license_spdx_id] || comp["license_spdx_id"] || "NOASSERTION",
        "copyrightText" => "NOASSERTION",
        "externalRefs" => [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceType" => "purl",
            "referenceLocator" => comp[:purl] || comp["purl"]
          }
        ]
      }
    end

    def build_licenses(spdx_id)
      return [] unless spdx_id.present?

      [{ "license" => { "id" => spdx_id } }]
    end

    def build_dependency_graph(components)
      # Build dependency relationships
      components.select { |c| c[:dependency_type] == "direct" || c["dependency_type"] == "direct" }.map do |comp|
        purl = comp[:purl] || comp["purl"]
        {
          "ref" => purl,
          "dependsOn" => []
        }
      end
    end

    def build_spdx_relationships(components)
      components.map do |comp|
        purl = comp[:purl] || comp["purl"]
        {
          "spdxElementId" => "SPDXRef-DOCUMENT",
          "relationshipType" => "DESCRIBES",
          "relatedSpdxElement" => "SPDXRef-Package-#{Digest::SHA256.hexdigest(purl)[0..15]}"
        }
      end
    end

    def persist_components(sbom, components)
      components.each do |comp|
        attrs = comp.is_a?(Hash) ? comp : comp.attributes
        SupplyChain::SbomComponent.create!(
          sbom: sbom,
          account: account,
          purl: attrs[:purl] || attrs["purl"],
          name: attrs[:name] || attrs["name"],
          version: attrs[:version] || attrs["version"],
          ecosystem: attrs[:ecosystem] || attrs["ecosystem"],
          dependency_type: attrs[:dependency_type] || attrs["dependency_type"] || "direct",
          depth: attrs[:depth] || attrs["depth"] || 0,
          license_spdx_id: attrs[:license_spdx_id] || attrs["license_spdx_id"],
          license_name: attrs[:license_name] || attrs["license_name"]
        )
      end
    end

    def persist_vulnerabilities(sbom, vulnerabilities)
      vulnerabilities.each do |vuln|
        component = sbom.components.find_by(purl: vuln[:component_purl])
        next unless component

        SupplyChain::SbomVulnerability.create!(
          sbom: sbom,
          component: component,
          account: account,
          vulnerability_id: vuln[:vulnerability_id],
          source: vuln[:source] || "osv",
          severity: vuln[:severity] || "unknown",
          cvss_score: vuln[:cvss_score],
          description: vuln[:description],
          fixed_version: vuln[:fixed_version]
        )
      end
    end

    def calculate_risk_score(sbom)
      SupplyChain::RiskCalculationService.new(sbom: sbom).calculate!
    end

    def version_newer?(v1, v2)
      return true if v2.nil?
      return false if v1.nil?

      Gem::Version.new(v1.gsub(/[^0-9.]/, "")) > Gem::Version.new(v2.gsub(/[^0-9.]/, ""))
    rescue ArgumentError
      false
    end
  end
end
