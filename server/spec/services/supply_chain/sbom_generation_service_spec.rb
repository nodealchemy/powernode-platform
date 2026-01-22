# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::SbomGenerationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, :owner, account: account) }
  let(:repository) { nil }
  let(:options) { {} }
  let(:service) { described_class.new(account: account, repository: repository, options: options) }

  describe "#initialize" do
    it "initializes with required account parameter" do
      expect(service.account).to eq(account)
      expect(service.repository).to be_nil
      expect(service.options).to eq({})
    end

    it "initializes with optional repository parameter" do
      repo = double("Repository", name: "test-repo")
      service = described_class.new(account: account, repository: repo)

      expect(service.repository).to eq(repo)
    end

    it "initializes with options hash" do
      opts = { branch: "main", commit_sha: "abc123" }
      service = described_class.new(account: account, options: opts)

      expect(service.options[:branch]).to eq("main")
      expect(service.options[:commit_sha]).to eq("abc123")
    end

    it "converts options to indifferent access" do
      opts = { "branch" => "main", commit_sha: "abc123" }
      service = described_class.new(account: account, options: opts)

      expect(service.options[:branch]).to eq("main")
      expect(service.options["commit_sha"]).to eq("abc123")
    end
  end

  describe "#generate" do
    let(:source_path) { Dir.mktmpdir }
    let(:npm_generator) { instance_double("SupplyChain::Generators::NpmGenerator") }
    let(:component_data) do
      {
        purl: "pkg:npm/react@18.2.0",
        name: "react",
        version: "18.2.0",
        ecosystem: "npm",
        dependency_type: "direct",
        depth: 0,
        license_spdx_id: "MIT",
        license_name: "MIT License"
      }
    end
    let(:vulnerability_data) do
      {
        component_purl: "pkg:npm/react@18.2.0",
        vulnerability_id: "CVE-2023-12345",
        source: "osv",
        severity: "high",
        cvss_score: 7.5,
        description: "Test vulnerability",
        fixed_version: "18.2.1"
      }
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow_any_instance_of(SupplyChain::Sbom).to receive(:verify_ntia_compliance).and_return(true)
    end

    after do
      FileUtils.remove_entry(source_path)
    end

    context "format validation" do
      it "accepts supported CycloneDX 1.5 format" do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path, format: "cyclonedx_1_5")

        expect(sbom.format).to eq("cyclonedx_1_5")
      end

      it "accepts supported CycloneDX 1.6 format" do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path, format: "cyclonedx_1_6")

        expect(sbom.format).to eq("cyclonedx_1_6")
      end

      it "accepts supported SPDX 2.3 format" do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path, format: "spdx_2_3")

        expect(sbom.format).to eq("spdx_2_3")
      end

      it "raises error for unsupported format" do
        expect do
          service.generate(source_path: source_path, format: "invalid_format")
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          /Unsupported format: invalid_format/
        )
      end
    end

    context "ecosystem detection" do
      it "detects npm ecosystem from package.json" do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom).to be_a(SupplyChain::Sbom)
        expect(sbom.status).to eq("completed")
      end

      it "detects gem ecosystem from Gemfile" do
        File.write(File.join(source_path, "Gemfile"), "")
        gem_generator = instance_double("SupplyChain::Generators::GemGenerator")
        allow(SupplyChain::Generators::GemGenerator).to receive(:new).and_return(gem_generator)
        allow(gem_generator).to receive(:generate).and_return({ components: [component_data.merge(ecosystem: "gem")], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "detects pip ecosystem from requirements.txt" do
        File.write(File.join(source_path, "requirements.txt"), "")
        pip_generator = instance_double("SupplyChain::Generators::PipGenerator")
        allow(SupplyChain::Generators::PipGenerator).to receive(:new).and_return(pip_generator)
        allow(pip_generator).to receive(:generate).and_return({ components: [component_data.merge(ecosystem: "pip")], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "detects pip ecosystem from Pipfile" do
        File.write(File.join(source_path, "Pipfile"), "")
        pip_generator = instance_double("SupplyChain::Generators::PipGenerator")
        allow(SupplyChain::Generators::PipGenerator).to receive(:new).and_return(pip_generator)
        allow(pip_generator).to receive(:generate).and_return({ components: [component_data.merge(ecosystem: "pip")], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "detects maven ecosystem from pom.xml" do
        File.write(File.join(source_path, "pom.xml"), "")
        maven_generator = instance_double("SupplyChain::Generators::MavenGenerator")
        allow(SupplyChain::Generators::MavenGenerator).to receive(:new).and_return(maven_generator)
        allow(maven_generator).to receive(:generate).and_return({ components: [component_data.merge(ecosystem: "maven")], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "detects go ecosystem from go.mod" do
        File.write(File.join(source_path, "go.mod"), "")
        go_generator = instance_double("SupplyChain::Generators::GoGenerator")
        allow(SupplyChain::Generators::GoGenerator).to receive(:new).and_return(go_generator)
        allow(go_generator).to receive(:generate).and_return({ components: [component_data.merge(ecosystem: "go")], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "detects cargo ecosystem from Cargo.toml" do
        File.write(File.join(source_path, "Cargo.toml"), "")
        cargo_generator = instance_double("SupplyChain::Generators::CargoGenerator")
        allow(SupplyChain::Generators::CargoGenerator).to receive(:new).and_return(cargo_generator)
        allow(cargo_generator).to receive(:generate).and_return({ components: [component_data.merge(ecosystem: "cargo")], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "detects multiple ecosystems" do
        File.write(File.join(source_path, "package.json"), '{}')
        File.write(File.join(source_path, "Gemfile"), "")

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: []
        })

        gem_generator = instance_double("SupplyChain::Generators::GemGenerator")
        allow(SupplyChain::Generators::GemGenerator).to receive(:new).and_return(gem_generator)
        allow(gem_generator).to receive(:generate).and_return({
          components: [component_data.merge(ecosystem: "gem", purl: "pkg:gem/rails@7.0.0")],
          vulnerabilities: []
        })

        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.component_count).to eq(2)
      end

      it "raises error when no ecosystems detected" do
        expect do
          service.generate(source_path: source_path)
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          "No supported ecosystems detected"
        )
      end
    end

    context "custom ecosystem list" do
      it "uses provided ecosystems list instead of detection" do
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path, ecosystems: ["npm"])

        expect(sbom.status).to eq("completed")
      end

      it "raises error for unsupported ecosystem in custom list" do
        expect do
          service.generate(source_path: source_path, ecosystems: ["invalid"])
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          /Unsupported ecosystem: invalid/
        )
      end
    end

    context "SBOM record creation" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)
      end

      it "creates SBOM with draft status initially" do
        expect do
          service.generate(source_path: source_path)
        end.to change(SupplyChain::Sbom, :count).by(1)

        sbom = SupplyChain::Sbom.last
        expect(sbom.account).to eq(account)
        expect(sbom.format).to eq("cyclonedx_1_5")
      end

      it "sets SBOM status to generating" do
        sbom = service.generate(source_path: source_path)

        expect(sbom.status).to eq("completed")
      end

      it "includes user in options when provided" do
        service = described_class.new(account: account, options: { user: user })
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.created_by).to eq(user)
      end

      it "includes branch and commit_sha when provided" do
        service = described_class.new(account: account, options: { branch: "main", commit_sha: "abc123" })
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.branch).to eq("main")
        expect(sbom.commit_sha).to eq("abc123")
      end

      it "generates SBOM name from options" do
        service = described_class.new(account: account, options: { name: "Custom SBOM Name" })
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.name).to eq("Custom SBOM Name")
      end

      it "generates SBOM name from repository when no name provided" do
        repo = create(:devops_repository, account: account, name: "test-repo")
        service = described_class.new(account: account, repository: repo, options: { branch: "main" })
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({ components: [component_data], vulnerabilities: [] })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.name).to match(/test-repo-main-\d{8}/)
      end
    end

    context "component persistence" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
      end

      it "persists components from generator results" do
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: []
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.components.count).to eq(1)
        component = sbom.components.first
        expect(component.purl).to eq("pkg:npm/react@18.2.0")
        expect(component.name).to eq("react")
        expect(component.version).to eq("18.2.0")
        expect(component.ecosystem).to eq("npm")
        expect(component.dependency_type).to eq("direct")
        expect(component.depth).to eq(0)
        expect(component.license_spdx_id).to eq("MIT")
        expect(component.license_name).to eq("MIT License")
      end

      it "persists multiple components" do
        components = [
          component_data,
          component_data.merge(purl: "pkg:npm/vue@3.0.0", name: "vue", version: "3.0.0")
        ]
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: components,
          vulnerabilities: []
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.components.count).to eq(2)
        expect(sbom.component_count).to eq(2)
      end
    end

    context "vulnerability persistence" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
      end

      it "persists vulnerabilities linked to components" do
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: [vulnerability_data]
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.vulnerabilities.count).to eq(1)
        vuln = sbom.vulnerabilities.first
        expect(vuln.vulnerability_id).to eq("CVE-2023-12345")
        expect(vuln.source).to eq("osv")
        expect(vuln.severity).to eq("high")
        expect(vuln.cvss_score).to eq(7.5)
        expect(vuln.description).to eq("Test vulnerability")
        expect(vuln.fixed_version).to eq("18.2.1")
        expect(vuln.component.purl).to eq("pkg:npm/react@18.2.0")
      end

      it "skips vulnerabilities for non-existent components" do
        orphan_vuln = vulnerability_data.merge(component_purl: "pkg:npm/nonexistent@1.0.0")
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: [orphan_vuln]
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.vulnerabilities.count).to eq(0)
      end

      it "updates vulnerability count in SBOM" do
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: [vulnerability_data]
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)

        sbom = service.generate(source_path: source_path)

        expect(sbom.vulnerability_count).to eq(1)
      end
    end

    context "CycloneDX document generation" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: []
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)
      end

      it "generates CycloneDX 1.5 document" do
        sbom = service.generate(source_path: source_path, format: "cyclonedx_1_5")

        doc = sbom.document
        expect(doc["bomFormat"]).to eq("CycloneDX")
        expect(doc["specVersion"]).to eq("1.5")
        expect(doc["serialNumber"]).to start_with("urn:uuid:")
        expect(doc["version"]).to eq(1)
      end

      it "generates CycloneDX 1.6 document" do
        sbom = service.generate(source_path: source_path, format: "cyclonedx_1_6")

        doc = sbom.document
        expect(doc["bomFormat"]).to eq("CycloneDX")
        expect(doc["specVersion"]).to eq("1.6")
      end

      it "includes metadata in document" do
        sbom = service.generate(source_path: source_path)

        doc = sbom.document
        expect(doc["metadata"]["timestamp"]).to be_present
        expect(doc["metadata"]["tools"]).to be_an(Array)
        expect(doc["metadata"]["tools"].first["vendor"]).to eq("Powernode")
        expect(doc["metadata"]["authors"]).to be_an(Array)
        expect(doc["metadata"]["authors"].first["name"]).to eq(account.name)
      end

      it "includes component information in document" do
        sbom = service.generate(source_path: source_path)

        doc = sbom.document
        expect(doc["components"]).to be_an(Array)
        expect(doc["components"].length).to eq(1)

        component = doc["components"].first
        expect(component["type"]).to eq("library")
        expect(component["name"]).to eq("react")
        expect(component["version"]).to eq("18.2.0")
        expect(component["purl"]).to eq("pkg:npm/react@18.2.0")
        expect(component["bom-ref"]).to eq("pkg:npm/react@18.2.0")
      end

      it "includes license information when present" do
        sbom = service.generate(source_path: source_path)

        doc = sbom.document
        component = doc["components"].first
        expect(component["licenses"]).to be_an(Array)
        expect(component["licenses"].first["license"]["id"]).to eq("MIT")
      end

      it "includes dependency graph" do
        sbom = service.generate(source_path: source_path)

        doc = sbom.document
        expect(doc["dependencies"]).to be_an(Array)
      end
    end

    context "SPDX document generation" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: []
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)
      end

      it "generates SPDX 2.3 document" do
        sbom = service.generate(source_path: source_path, format: "spdx_2_3")

        doc = sbom.document
        expect(doc["spdxVersion"]).to eq("SPDX-2.3")
        expect(doc["dataLicense"]).to eq("CC0-1.0")
        expect(doc["SPDXID"]).to eq("SPDXRef-DOCUMENT")
        expect(doc["documentNamespace"]).to start_with("https://spdx.org/spdxdocs/")
      end

      it "includes creation info in document" do
        sbom = service.generate(source_path: source_path, format: "spdx_2_3")

        doc = sbom.document
        expect(doc["creationInfo"]["created"]).to be_present
        expect(doc["creationInfo"]["creators"]).to be_an(Array)
        expect(doc["creationInfo"]["creators"]).to include("Tool: Powernode-SupplyChainManager-1.0.0")
        expect(doc["creationInfo"]["creators"]).to include("Organization: #{account.name}")
      end

      it "includes package information" do
        sbom = service.generate(source_path: source_path, format: "spdx_2_3")

        doc = sbom.document
        expect(doc["packages"]).to be_an(Array)
        expect(doc["packages"].length).to eq(1)

        package = doc["packages"].first
        expect(package["SPDXID"]).to start_with("SPDXRef-Package-")
        expect(package["name"]).to eq("react")
        expect(package["versionInfo"]).to eq("18.2.0")
        expect(package["downloadLocation"]).to eq("NOASSERTION")
        expect(package["licenseConcluded"]).to eq("MIT")
        expect(package["licenseDeclared"]).to eq("MIT")
      end

      it "includes external references with PURL" do
        sbom = service.generate(source_path: source_path, format: "spdx_2_3")

        doc = sbom.document
        package = doc["packages"].first
        expect(package["externalRefs"]).to be_an(Array)

        purl_ref = package["externalRefs"].first
        expect(purl_ref["referenceCategory"]).to eq("PACKAGE-MANAGER")
        expect(purl_ref["referenceType"]).to eq("purl")
        expect(purl_ref["referenceLocator"]).to eq("pkg:npm/react@18.2.0")
      end

      it "includes relationships" do
        sbom = service.generate(source_path: source_path, format: "spdx_2_3")

        doc = sbom.document
        expect(doc["relationships"]).to be_an(Array)
        expect(doc["relationships"].first["spdxElementId"]).to eq("SPDXRef-DOCUMENT")
        expect(doc["relationships"].first["relationshipType"]).to eq("DESCRIBES")
      end
    end

    context "risk calculation trigger" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: []
        })
      end

      it "triggers risk calculation after generation" do
        risk_service = instance_double(SupplyChain::RiskCalculationService)
        expect(SupplyChain::RiskCalculationService).to receive(:new).with(sbom: kind_of(SupplyChain::Sbom)).and_return(risk_service)
        expect(risk_service).to receive(:calculate!)

        service.generate(source_path: source_path)
      end
    end

    context "NTIA compliance check" do
      before do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_return({
          components: [component_data],
          vulnerabilities: []
        })
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!)
      end

      it "verifies NTIA compliance after generation" do
        expect_any_instance_of(SupplyChain::Sbom).to receive(:verify_ntia_compliance)

        service.generate(source_path: source_path)
      end
    end

    context "error handling" do
      it "handles generator failures gracefully" do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_raise(StandardError, "Generator failed")

        expect do
          service.generate(source_path: source_path)
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          "SBOM generation failed: Generator failed"
        )

        sbom = SupplyChain::Sbom.last
        expect(sbom.status).to eq("failed")
        expect(sbom.metadata["error"]).to eq("Generator failed")
      end

      it "logs error when generation fails" do
        File.write(File.join(source_path, "package.json"), '{}')
        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:generate).and_raise(StandardError, "Test error")

        expect(Rails.logger).to receive(:error).with(/Generation failed: Test error/)

        expect do
          service.generate(source_path: source_path)
        end.to raise_error(SupplyChain::SbomGenerationService::GenerationError)
      end
    end
  end

  describe "#generate_from_lockfiles" do
    let(:package_lock_content) { '{"name": "test", "version": "1.0.0"}' }
    let(:gemfile_lock_content) { "GEM\n  remote: https://rubygems.org/" }
    let(:npm_generator) { instance_double("SupplyChain::Generators::NpmGenerator") }
    let(:gem_generator) { instance_double("SupplyChain::Generators::GemGenerator") }
    let(:component_data) do
      {
        purl: "pkg:npm/react@18.2.0",
        name: "react",
        version: "18.2.0",
        ecosystem: "npm",
        dependency_type: "direct",
        depth: 0
      }
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow_any_instance_of(SupplyChain::Sbom).to receive(:verify_ntia_compliance).and_return(true)
    end

    context "lockfile parsing" do
      it "parses package-lock.json" do
        lockfiles = [
          { filename: "package-lock.json", content: package_lock_content }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_return({
          components: [component_data]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.status).to eq("completed")
        expect(sbom.components.count).to eq(1)
      end

      it "parses Gemfile.lock" do
        lockfiles = [
          { filename: "Gemfile.lock", content: gemfile_lock_content }
        ]

        allow(SupplyChain::Generators::GemGenerator).to receive(:new).and_return(gem_generator)
        allow(gem_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "gem")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses yarn.lock" do
        lockfiles = [
          { filename: "yarn.lock", content: "# yarn lockfile v1" }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_return({
          components: [component_data]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses pnpm-lock.yaml" do
        lockfiles = [
          { filename: "pnpm-lock.yaml", content: "lockfileVersion: 5.3" }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_return({
          components: [component_data]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses requirements.txt" do
        lockfiles = [
          { filename: "requirements.txt", content: "requests==2.28.0" }
        ]

        pip_generator = instance_double("SupplyChain::Generators::PipGenerator")
        allow(SupplyChain::Generators::PipGenerator).to receive(:new).and_return(pip_generator)
        allow(pip_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "pip")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses Pipfile.lock" do
        lockfiles = [
          { filename: "Pipfile.lock", content: '{"_meta": {}}' }
        ]

        pip_generator = instance_double("SupplyChain::Generators::PipGenerator")
        allow(SupplyChain::Generators::PipGenerator).to receive(:new).and_return(pip_generator)
        allow(pip_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "pip")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses poetry.lock" do
        lockfiles = [
          { filename: "poetry.lock", content: "[[package]]" }
        ]

        pip_generator = instance_double("SupplyChain::Generators::PipGenerator")
        allow(SupplyChain::Generators::PipGenerator).to receive(:new).and_return(pip_generator)
        allow(pip_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "pip")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses go.sum" do
        lockfiles = [
          { filename: "go.sum", content: "github.com/pkg/errors v0.9.1 h1:FEBLx1zS214owpjy7qsBeixbURkuhQAwrK5UwLGTwt4=" }
        ]

        go_generator = instance_double("SupplyChain::Generators::GoGenerator")
        allow(SupplyChain::Generators::GoGenerator).to receive(:new).and_return(go_generator)
        allow(go_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "go")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses Cargo.lock" do
        lockfiles = [
          { filename: "Cargo.lock", content: "version = 3" }
        ]

        cargo_generator = instance_double("SupplyChain::Generators::CargoGenerator")
        allow(SupplyChain::Generators::CargoGenerator).to receive(:new).and_return(cargo_generator)
        allow(cargo_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "cargo")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end

      it "parses gradle.lockfile" do
        lockfiles = [
          { filename: "gradle.lockfile", content: "# Gradle lockfile" }
        ]

        maven_generator = instance_double("SupplyChain::Generators::MavenGenerator")
        allow(SupplyChain::Generators::MavenGenerator).to receive(:new).and_return(maven_generator)
        allow(maven_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "maven")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end
    end

    context "multiple lockfiles" do
      it "combines components from multiple lockfiles" do
        lockfiles = [
          { filename: "package-lock.json", content: package_lock_content },
          { filename: "Gemfile.lock", content: gemfile_lock_content }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_return({
          components: [component_data]
        })

        allow(SupplyChain::Generators::GemGenerator).to receive(:new).and_return(gem_generator)
        allow(gem_generator).to receive(:parse_lockfile).and_return({
          components: [component_data.merge(ecosystem: "gem", purl: "pkg:gem/rails@7.0.0")]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(2)
      end
    end

    context "unknown file types" do
      it "skips lockfiles with unknown extensions" do
        lockfiles = [
          { filename: "package-lock.json", content: package_lock_content },
          { filename: "unknown.txt", content: "unknown content" }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_return({
          components: [component_data]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles)

        expect(sbom.components.count).to eq(1)
      end
    end

    context "format validation" do
      it "accepts valid format" do
        lockfiles = [
          { filename: "package-lock.json", content: package_lock_content }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_return({
          components: [component_data]
        })

        sbom = service.generate_from_lockfiles(lockfiles: lockfiles, format: "cyclonedx_1_6")

        expect(sbom.format).to eq("cyclonedx_1_6")
      end

      it "raises error for invalid format" do
        lockfiles = [
          { filename: "package-lock.json", content: package_lock_content }
        ]

        expect do
          service.generate_from_lockfiles(lockfiles: lockfiles, format: "invalid")
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          /Unsupported format: invalid/
        )
      end
    end

    context "error handling" do
      it "handles parsing failures" do
        lockfiles = [
          { filename: "package-lock.json", content: package_lock_content }
        ]

        allow(SupplyChain::Generators::NpmGenerator).to receive(:new).and_return(npm_generator)
        allow(npm_generator).to receive(:parse_lockfile).and_raise(StandardError, "Parse error")

        expect do
          service.generate_from_lockfiles(lockfiles: lockfiles)
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          "SBOM generation failed: Parse error"
        )

        sbom = SupplyChain::Sbom.last
        expect(sbom.status).to eq("failed")
      end
    end
  end

  describe "#merge_sboms" do
    let!(:sbom1) { create(:supply_chain_sbom, account: account, format: "cyclonedx_1_5") }
    let!(:sbom2) { create(:supply_chain_sbom, account: account, format: "cyclonedx_1_5") }
    let!(:component1) do
      create(:supply_chain_sbom_component,
        sbom: sbom1,
        account: account,
        purl: "pkg:npm/react@18.2.0",
        name: "react",
        version: "18.2.0",
        ecosystem: "npm"
      )
    end
    let!(:component2) do
      create(:supply_chain_sbom_component,
        sbom: sbom2,
        account: account,
        purl: "pkg:npm/vue@3.0.0",
        name: "vue",
        version: "3.0.0",
        ecosystem: "npm"
      )
    end

    before do
      allow_any_instance_of(SupplyChain::Sbom).to receive(:verify_ntia_compliance).and_return(true)
    end

    context "merging multiple SBOMs" do
      it "creates new SBOM with components from all source SBOMs" do
        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        expect(merged).to be_a(SupplyChain::Sbom)
        expect(merged.status).to eq("completed")
        expect(merged.components.count).to eq(2)
      end

      it "uses format from first SBOM when not specified" do
        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        expect(merged.format).to eq("cyclonedx_1_5")
      end

      it "uses specified format when provided" do
        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id], format: "spdx_2_3")

        expect(merged.format).to eq("spdx_2_3")
      end
    end

    context "component deduplication" do
      it "deduplicates components by PURL" do
        duplicate_component = create(:supply_chain_sbom_component,
          sbom: sbom2,
          account: account,
          purl: "pkg:npm/react@18.2.0",
          name: "react",
          version: "18.2.0",
          ecosystem: "npm"
        )

        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        expect(merged.components.count).to eq(2)
        expect(merged.components.pluck(:purl).uniq.count).to eq(2)
      end

      it "keeps newer version when duplicate PURLs exist" do
        # Create older version in sbom1
        old_component = create(:supply_chain_sbom_component,
          sbom: sbom1,
          account: account,
          purl: "pkg:npm/lodash@4.17.20",
          name: "lodash",
          version: "4.17.20",
          ecosystem: "npm"
        )

        # Create newer version in sbom2
        new_component = create(:supply_chain_sbom_component,
          sbom: sbom2,
          account: account,
          purl: "pkg:npm/lodash@4.17.21",
          name: "lodash",
          version: "4.17.21",
          ecosystem: "npm"
        )

        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        lodash_component = merged.components.find_by(name: "lodash")
        expect(lodash_component.version).to eq("4.17.21")
      end

      it "handles version comparison with non-semantic versions" do
        # Create component with non-standard version format
        component_with_prefix = create(:supply_chain_sbom_component,
          sbom: sbom1,
          account: account,
          purl: "pkg:npm/test@v1.0.0",
          name: "test",
          version: "v1.0.0",
          ecosystem: "npm"
        )

        component_newer = create(:supply_chain_sbom_component,
          sbom: sbom2,
          account: account,
          purl: "pkg:npm/test@v2.0.0",
          name: "test",
          version: "v2.0.0",
          ecosystem: "npm"
        )

        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        test_component = merged.components.find_by(name: "test")
        expect(test_component.version).to eq("v2.0.0")
      end

      it "handles invalid version comparison gracefully" do
        component_invalid1 = create(:supply_chain_sbom_component,
          sbom: sbom1,
          account: account,
          purl: "pkg:npm/invalid@latest",
          name: "invalid",
          version: "latest",
          ecosystem: "npm"
        )

        component_invalid2 = create(:supply_chain_sbom_component,
          sbom: sbom2,
          account: account,
          purl: "pkg:npm/invalid@stable",
          name: "invalid",
          version: "stable",
          ecosystem: "npm"
        )

        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        # Should not raise error, picks one version
        expect(merged.components.where(name: "invalid").count).to eq(1)
      end
    end

    context "error handling" do
      it "raises error when no SBOMs found" do
        expect do
          service.merge_sboms(sbom_ids: [])
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          "No SBOMs found to merge"
        )
      end

      it "raises error when SBOMs don't belong to account" do
        other_account = create(:account)
        other_sbom = create(:supply_chain_sbom, account: other_account)

        expect do
          service.merge_sboms(sbom_ids: [other_sbom.id])
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          "No SBOMs found to merge"
        )
      end

      it "filters out non-existent SBOM IDs" do
        merged = service.merge_sboms(sbom_ids: [sbom1.id, "non-existent-id"])

        expect(merged.components.count).to eq(1)
      end
    end

    context "merged SBOM properties" do
      it "sets correct component count" do
        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        expect(merged.component_count).to eq(2)
      end

      it "generates proper document structure" do
        merged = service.merge_sboms(sbom_ids: [sbom1.id, sbom2.id])

        doc = merged.document
        expect(doc["bomFormat"]).to eq("CycloneDX")
        expect(doc["components"]).to be_an(Array)
        expect(doc["components"].length).to eq(2)
      end
    end
  end

  describe "private methods" do
    describe "#validate_format!" do
      it "accepts cyclonedx_1_5" do
        expect do
          service.send(:validate_format!, "cyclonedx_1_5")
        end.not_to raise_error
      end

      it "accepts cyclonedx_1_6" do
        expect do
          service.send(:validate_format!, "cyclonedx_1_6")
        end.not_to raise_error
      end

      it "accepts spdx_2_3" do
        expect do
          service.send(:validate_format!, "spdx_2_3")
        end.not_to raise_error
      end

      it "rejects unsupported format" do
        expect do
          service.send(:validate_format!, "invalid")
        end.to raise_error(
          SupplyChain::SbomGenerationService::GenerationError,
          "Unsupported format: invalid. Supported: cyclonedx_1_5, cyclonedx_1_6, spdx_2_3"
        )
      end
    end

    describe "#detect_ecosystems" do
      let(:source_path) { Dir.mktmpdir }

      after do
        FileUtils.remove_entry(source_path)
      end

      it "detects npm from package.json" do
        File.write(File.join(source_path, "package.json"), '{}')

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("npm")
      end

      it "detects gem from Gemfile" do
        File.write(File.join(source_path, "Gemfile"), "")

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("gem")
      end

      it "detects pip from requirements.txt" do
        File.write(File.join(source_path, "requirements.txt"), "")

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("pip")
      end

      it "detects pip from Pipfile" do
        File.write(File.join(source_path, "Pipfile"), "")

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("pip")
      end

      it "detects maven from pom.xml" do
        File.write(File.join(source_path, "pom.xml"), "")

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("maven")
      end

      it "detects go from go.mod" do
        File.write(File.join(source_path, "go.mod"), "")

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("go")
      end

      it "detects cargo from Cargo.toml" do
        File.write(File.join(source_path, "Cargo.toml"), "")

        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to include("cargo")
      end

      it "returns empty array when no ecosystems detected" do
        ecosystems = service.send(:detect_ecosystems, source_path)

        expect(ecosystems).to be_empty
      end
    end

    describe "#detect_ecosystem_from_file" do
      it "detects npm from package-lock.json" do
        expect(service.send(:detect_ecosystem_from_file, "package-lock.json")).to eq("npm")
      end

      it "detects npm from npm-shrinkwrap.json" do
        expect(service.send(:detect_ecosystem_from_file, "npm-shrinkwrap.json")).to eq("npm")
      end

      it "detects npm from yarn.lock" do
        expect(service.send(:detect_ecosystem_from_file, "yarn.lock")).to eq("npm")
      end

      it "detects npm from pnpm-lock.yaml" do
        expect(service.send(:detect_ecosystem_from_file, "pnpm-lock.yaml")).to eq("npm")
      end

      it "detects gem from Gemfile.lock" do
        expect(service.send(:detect_ecosystem_from_file, "Gemfile.lock")).to eq("gem")
      end

      it "detects pip from requirements.txt" do
        expect(service.send(:detect_ecosystem_from_file, "requirements.txt")).to eq("pip")
      end

      it "detects pip from Pipfile.lock" do
        expect(service.send(:detect_ecosystem_from_file, "Pipfile.lock")).to eq("pip")
      end

      it "detects pip from poetry.lock" do
        expect(service.send(:detect_ecosystem_from_file, "poetry.lock")).to eq("pip")
      end

      it "detects maven from pom.xml" do
        expect(service.send(:detect_ecosystem_from_file, "pom.xml")).to eq("maven")
      end

      it "detects maven from gradle.lockfile" do
        expect(service.send(:detect_ecosystem_from_file, "gradle.lockfile")).to eq("maven")
      end

      it "detects go from go.sum" do
        expect(service.send(:detect_ecosystem_from_file, "go.sum")).to eq("go")
      end

      it "detects cargo from Cargo.lock" do
        expect(service.send(:detect_ecosystem_from_file, "Cargo.lock")).to eq("cargo")
      end

      it "returns nil for unknown file" do
        expect(service.send(:detect_ecosystem_from_file, "unknown.txt")).to be_nil
      end

      it "handles case-insensitive filenames" do
        expect(service.send(:detect_ecosystem_from_file, "PACKAGE-LOCK.JSON")).to eq("npm")
      end
    end

    describe "#build_generator" do
      it "builds npm generator" do
        generator = service.send(:build_generator, "npm", "/path/to/source")

        expect(generator).to be_a(SupplyChain::Generators::NpmGenerator)
      end

      it "raises error for unsupported ecosystem" do
        expect do
          service.send(:build_generator, "unsupported", "/path/to/source")
        end.to raise_error(
          SupplyChain::SbomGenerationService::UnsupportedEcosystemError,
          "Unsupported ecosystem: unsupported"
        )
      end
    end

    describe "#version_newer?" do
      it "returns true when v1 is newer than v2" do
        expect(service.send(:version_newer?, "2.0.0", "1.0.0")).to be true
      end

      it "returns false when v1 is older than v2" do
        expect(service.send(:version_newer?, "1.0.0", "2.0.0")).to be false
      end

      it "returns true when v2 is nil" do
        expect(service.send(:version_newer?, "1.0.0", nil)).to be true
      end

      it "returns false when v1 is nil" do
        expect(service.send(:version_newer?, nil, "1.0.0")).to be false
      end

      it "handles version strings with prefixes" do
        expect(service.send(:version_newer?, "v2.0.0", "v1.0.0")).to be true
      end

      it "handles invalid version formats gracefully" do
        expect(service.send(:version_newer?, "latest", "stable")).to be false
      end
    end
  end
end
