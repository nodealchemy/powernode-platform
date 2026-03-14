# frozen_string_literal: true

require "rails_helper"

# Test subclass to test the abstract BaseGenerator
class TestGenerator < SupplyChain::Generators::BaseGenerator
  def ecosystem
    "test"
  end
end

RSpec.describe SupplyChain::Generators::BaseGenerator do
  let(:account) { create(:account) }
  let(:source_path) { Dir.mktmpdir }
  let(:options) { {} }
  let(:generator) { TestGenerator.new(account: account, source_path: source_path, options: options) }

  after do
    FileUtils.remove_entry(source_path) if source_path && Dir.exist?(source_path)
  end

  describe "#initialize" do
    it "sets account attribute" do
      expect(generator.account).to eq(account)
    end

    it "sets source_path attribute" do
      expect(generator.source_path).to eq(source_path)
    end

    it "sets options attribute" do
      expect(generator.options).to eq({})
    end

    it "converts options to indifferent access with string keys" do
      opts = { "branch" => "main", commit_sha: "abc123" }
      gen = TestGenerator.new(account: account, source_path: source_path, options: opts)

      expect(gen.options[:branch]).to eq("main")
      expect(gen.options["branch"]).to eq("main")
    end

    it "converts options to indifferent access with symbol keys" do
      opts = { branch: "main", "commit_sha" => "abc123" }
      gen = TestGenerator.new(account: account, source_path: source_path, options: opts)

      expect(gen.options[:commit_sha]).to eq("abc123")
      expect(gen.options["commit_sha"]).to eq("abc123")
    end

    it "handles nil options by defaulting to empty hash" do
      gen = TestGenerator.new(account: account, source_path: source_path)

      expect(gen.options).to eq({})
    end
  end

  describe "#generate" do
    it "raises NotImplementedError for base class" do
      base_gen = described_class.new(account: account, source_path: source_path)

      expect { base_gen.generate }.to raise_error(
        NotImplementedError,
        "SupplyChain::Generators::BaseGenerator must implement #generate"
      )
    end

    it "raises NotImplementedError with correct class name for subclass without implementation" do
      # Create a subclass that doesn't override generate
      stub_const("IncompleteGenerator", Class.new(described_class) do
        def ecosystem
          "incomplete"
        end
      end)

      gen = IncompleteGenerator.new(account: account, source_path: source_path)

      expect { gen.generate }.to raise_error(
        NotImplementedError,
        "IncompleteGenerator must implement #generate"
      )
    end
  end

  describe "#parse_lockfile" do
    it "raises NotImplementedError for base class" do
      base_gen = described_class.new(account: account, source_path: source_path)

      expect { base_gen.parse_lockfile("content") }.to raise_error(
        NotImplementedError,
        "SupplyChain::Generators::BaseGenerator must implement #parse_lockfile"
      )
    end

    it "raises NotImplementedError with correct class name for subclass without implementation" do
      stub_const("IncompleteGenerator", Class.new(described_class) do
        def ecosystem
          "incomplete"
        end
      end)

      gen = IncompleteGenerator.new(account: account, source_path: source_path)

      expect { gen.parse_lockfile("content") }.to raise_error(
        NotImplementedError,
        "IncompleteGenerator must implement #parse_lockfile"
      )
    end
  end

  describe "#ecosystem (protected)" do
    it "raises NotImplementedError for base class" do
      base_gen = described_class.new(account: account, source_path: source_path)

      expect { base_gen.send(:ecosystem) }.to raise_error(
        NotImplementedError,
        "SupplyChain::Generators::BaseGenerator must implement #ecosystem"
      )
    end

    it "returns correct ecosystem for TestGenerator subclass" do
      expect(generator.send(:ecosystem)).to eq("test")
    end
  end

  describe "#build_purl (protected)" do
    it "builds basic purl without namespace" do
      purl = generator.send(:build_purl, name: "lodash", version: "4.17.21")

      expect(purl).to eq("pkg:test/lodash@4.17.21")
    end

    it "builds purl with namespace" do
      purl = generator.send(:build_purl, name: "core", version: "1.0.0", namespace: "@angular")

      expect(purl).to eq("pkg:test/@angular/core@1.0.0")
    end

    it "builds purl without version when version is nil" do
      purl = generator.send(:build_purl, name: "lodash", version: nil)

      expect(purl).to eq("pkg:test/lodash")
    end

    it "builds purl without version when version is blank" do
      purl = generator.send(:build_purl, name: "lodash", version: "")

      expect(purl).to eq("pkg:test/lodash")
    end

    it "builds purl with namespace but no version" do
      purl = generator.send(:build_purl, name: "core", version: nil, namespace: "@angular")

      expect(purl).to eq("pkg:test/@angular/core")
    end

    it "includes version with special characters" do
      purl = generator.send(:build_purl, name: "react", version: "18.2.0-alpha.1")

      expect(purl).to eq("pkg:test/react@18.2.0-alpha.1")
    end
  end

  describe "#build_component (protected)" do
    it "returns correct hash structure with minimal attributes" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21")

      expect(component).to include(
        name: "lodash",
        version: "4.17.21",
        ecosystem: "test",
        dependency_type: "direct",
        depth: 0
      )
    end

    it "uses provided purl when given" do
      custom_purl = "pkg:npm/lodash@4.17.21"
      component = generator.send(:build_component, name: "lodash", version: "4.17.21", purl: custom_purl)

      expect(component[:purl]).to eq(custom_purl)
    end

    it "builds purl automatically when not provided" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21")

      expect(component[:purl]).to eq("pkg:test/lodash@4.17.21")
    end

    it "builds purl with namespace when provided in attrs" do
      component = generator.send(:build_component, name: "core", version: "1.0.0", namespace: "@angular")

      expect(component[:purl]).to eq("pkg:test/@angular/core@1.0.0")
      expect(component[:namespace]).to eq("@angular")
    end

    it "sets default dependency_type to direct" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21")

      expect(component[:dependency_type]).to eq("direct")
    end

    it "allows custom dependency_type" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21", dependency_type: "transitive")

      expect(component[:dependency_type]).to eq("transitive")
    end

    it "sets default depth to 0" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21")

      expect(component[:depth]).to eq(0)
    end

    it "allows custom depth" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21", depth: 3)

      expect(component[:depth]).to eq(3)
    end

    it "includes license_spdx_id when provided" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21", license_spdx_id: "MIT")

      expect(component[:license_spdx_id]).to eq("MIT")
    end

    it "includes license_name when provided" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21", license_name: "MIT License")

      expect(component[:license_name]).to eq("MIT License")
    end

    it "includes both license fields when provided" do
      component = generator.send(
        :build_component,
        name: "lodash",
        version: "4.17.21",
        license_spdx_id: "Apache-2.0",
        license_name: "Apache License 2.0"
      )

      expect(component[:license_spdx_id]).to eq("Apache-2.0")
      expect(component[:license_name]).to eq("Apache License 2.0")
    end

    it "sets license fields to nil when not provided" do
      component = generator.send(:build_component, name: "lodash", version: "4.17.21")

      expect(component).to have_key(:license_spdx_id)
      expect(component).to have_key(:license_name)
      expect(component[:license_spdx_id]).to be_nil
      expect(component[:license_name]).to be_nil
    end
  end

  describe "#read_file (private)" do
    it "returns nil when source_path is nil" do
      gen = TestGenerator.new(account: account, source_path: nil)

      result = gen.send(:read_file, "package.json")

      expect(result).to be_nil
    end

    it "returns nil when source_path is blank" do
      gen = TestGenerator.new(account: account, source_path: "")

      result = gen.send(:read_file, "package.json")

      expect(result).to be_nil
    end

    it "returns nil when file does not exist" do
      result = generator.send(:read_file, "nonexistent.json")

      expect(result).to be_nil
    end

    it "returns file contents when file exists" do
      file_content = '{"name": "test-package", "version": "1.0.0"}'
      File.write(File.join(source_path, "package.json"), file_content)

      result = generator.send(:read_file, "package.json")

      expect(result).to eq(file_content)
    end

    it "reads files in subdirectories" do
      subdir = File.join(source_path, "nested", "dir")
      FileUtils.mkdir_p(subdir)
      file_content = "nested content"
      File.write(File.join(subdir, "file.txt"), file_content)

      result = generator.send(:read_file, "nested/dir/file.txt")

      expect(result).to eq(file_content)
    end

    it "reads binary content correctly" do
      binary_content = "\x00\x01\x02\x03"
      File.binwrite(File.join(source_path, "binary.bin"), binary_content)

      result = generator.send(:read_file, "binary.bin")

      expect(result).to eq(binary_content)
    end
  end

  describe "#parse_json (private)" do
    before do
      allow(Rails.logger).to receive(:error)
    end

    it "parses valid JSON" do
      json_content = '{"name": "test", "version": "1.0.0"}'

      result = generator.send(:parse_json, json_content)

      expect(result).to eq({ "name" => "test", "version" => "1.0.0" })
    end

    it "parses JSON arrays" do
      json_content = '[1, 2, 3]'

      result = generator.send(:parse_json, json_content)

      expect(result).to eq([ 1, 2, 3 ])
    end

    it "parses nested JSON" do
      json_content = '{"dependencies": {"lodash": "^4.17.21"}}'

      result = generator.send(:parse_json, json_content)

      expect(result).to eq({ "dependencies" => { "lodash" => "^4.17.21" } })
    end

    it "returns nil for invalid JSON" do
      invalid_json = "{ invalid json }"

      result = generator.send(:parse_json, invalid_json)

      expect(result).to be_nil
    end

    it "logs error for invalid JSON" do
      invalid_json = "{ invalid json }"

      generator.send(:parse_json, invalid_json)

      expect(Rails.logger).to have_received(:error).with(/JSON parse error/)
    end

    it "returns nil for empty string" do
      result = generator.send(:parse_json, "")

      expect(result).to be_nil
    end
  end

  describe "#detect_license_from_text (private)" do
    context "MIT license" do
      it "detects MIT" do
        result = generator.send(:detect_license_from_text, "MIT")

        expect(result).to eq("MIT")
      end

      it "detects MIT case-insensitively" do
        result = generator.send(:detect_license_from_text, "mit")

        expect(result).to eq("MIT")
      end

      it "detects MIT License text" do
        result = generator.send(:detect_license_from_text, "MIT License")

        expect(result).to eq("MIT")
      end
    end

    context "Apache license" do
      it "detects Apache-2.0" do
        result = generator.send(:detect_license_from_text, "Apache 2.0")

        expect(result).to eq("Apache-2.0")
      end

      it "detects Apache License 2.0" do
        result = generator.send(:detect_license_from_text, "Apache License 2.0")

        expect(result).to eq("Apache-2.0")
      end

      it "detects Apache-2" do
        result = generator.send(:detect_license_from_text, "Apache-2")

        expect(result).to eq("Apache-2.0")
      end
    end

    context "BSD licenses" do
      it "detects BSD-3-Clause" do
        result = generator.send(:detect_license_from_text, "BSD 3-Clause")

        expect(result).to eq("BSD-3-Clause")
      end

      it "detects BSD-3" do
        result = generator.send(:detect_license_from_text, "BSD-3")

        expect(result).to eq("BSD-3-Clause")
      end

      it "detects BSD-2-Clause" do
        result = generator.send(:detect_license_from_text, "BSD 2-Clause")

        expect(result).to eq("BSD-2-Clause")
      end

      it "detects BSD-2" do
        result = generator.send(:detect_license_from_text, "BSD-2")

        expect(result).to eq("BSD-2-Clause")
      end
    end

    context "GPL licenses" do
      it "detects GPL-3.0-only" do
        result = generator.send(:detect_license_from_text, "GPL 3.0")

        expect(result).to eq("GPL-3.0-only")
      end

      it "detects GPL-3" do
        result = generator.send(:detect_license_from_text, "GPL-3")

        expect(result).to eq("GPL-3.0-only")
      end

      it "detects GPLv3" do
        result = generator.send(:detect_license_from_text, "GPLv3")

        expect(result).to eq("GPL-3.0-only")
      end

      it "detects GPL-2.0-only" do
        result = generator.send(:detect_license_from_text, "GPL 2.0")

        expect(result).to eq("GPL-2.0-only")
      end

      it "detects GPL-2" do
        result = generator.send(:detect_license_from_text, "GPL-2")

        expect(result).to eq("GPL-2.0-only")
      end

      it "detects GPLv2" do
        result = generator.send(:detect_license_from_text, "GPLv2")

        expect(result).to eq("GPL-2.0-only")
      end
    end

    context "LGPL licenses" do
      it "detects LGPL-3.0-only" do
        result = generator.send(:detect_license_from_text, "LGPL 3.0")

        expect(result).to eq("LGPL-3.0-only")
      end

      it "detects LGPL-3" do
        result = generator.send(:detect_license_from_text, "LGPL-3")

        expect(result).to eq("LGPL-3.0-only")
      end

      it "detects LGPLv3" do
        result = generator.send(:detect_license_from_text, "LGPLv3")

        expect(result).to eq("LGPL-3.0-only")
      end

      it "detects LGPL-2.1-only" do
        result = generator.send(:detect_license_from_text, "LGPL 2.1")

        expect(result).to eq("LGPL-2.1-only")
      end

      it "detects LGPL-2" do
        result = generator.send(:detect_license_from_text, "LGPL-2")

        expect(result).to eq("LGPL-2.1-only")
      end

      it "detects LGPLv2" do
        result = generator.send(:detect_license_from_text, "LGPLv2")

        expect(result).to eq("LGPL-2.1-only")
      end
    end

    context "MPL license" do
      it "detects MPL-2.0" do
        result = generator.send(:detect_license_from_text, "MPL 2.0")

        expect(result).to eq("MPL-2.0")
      end

      it "detects MPL-2" do
        result = generator.send(:detect_license_from_text, "MPL-2")

        expect(result).to eq("MPL-2.0")
      end

      it "detects Mozilla Public License 2.0" do
        result = generator.send(:detect_license_from_text, "Mozilla Public License 2.0")

        expect(result).to eq("MPL-2.0")
      end
    end

    context "ISC license" do
      it "detects ISC" do
        result = generator.send(:detect_license_from_text, "ISC")

        expect(result).to eq("ISC")
      end

      it "detects ISC case-insensitively" do
        result = generator.send(:detect_license_from_text, "isc")

        expect(result).to eq("ISC")
      end

      it "detects ISC License" do
        result = generator.send(:detect_license_from_text, "ISC License")

        expect(result).to eq("ISC")
      end
    end

    context "Unlicense" do
      it "detects Unlicense" do
        result = generator.send(:detect_license_from_text, "Unlicense")

        expect(result).to eq("Unlicense")
      end

      it "detects Unlicense case-insensitively" do
        result = generator.send(:detect_license_from_text, "UNLICENSE")

        expect(result).to eq("Unlicense")
      end

      it "detects The Unlicense" do
        result = generator.send(:detect_license_from_text, "The Unlicense")

        expect(result).to eq("Unlicense")
      end
    end

    context "unknown or empty text" do
      it "returns nil for unknown license text" do
        result = generator.send(:detect_license_from_text, "Proprietary License")

        expect(result).to be_nil
      end

      it "returns nil for empty string" do
        result = generator.send(:detect_license_from_text, "")

        expect(result).to be_nil
      end

      it "returns nil for nil input" do
        result = generator.send(:detect_license_from_text, nil)

        expect(result).to be_nil
      end

      it "returns nil for whitespace-only text" do
        result = generator.send(:detect_license_from_text, "   ")

        expect(result).to be_nil
      end

      it "returns nil for unrecognized license formats" do
        result = generator.send(:detect_license_from_text, "Custom License v1.0")

        expect(result).to be_nil
      end
    end
  end

  describe "#log_info (private)" do
    it "logs info message with class name prefix" do
      expect(Rails.logger).to receive(:info).with("[TestGenerator] Test message")

      generator.send(:log_info, "Test message")
    end
  end

  describe "#log_warn (private)" do
    it "logs warning message with class name prefix" do
      expect(Rails.logger).to receive(:warn).with("[TestGenerator] Warning message")

      generator.send(:log_warn, "Warning message")
    end
  end

  describe "#log_error (private)" do
    it "logs error message with class name prefix" do
      expect(Rails.logger).to receive(:error).with("[TestGenerator] Error message")

      generator.send(:log_error, "Error message")
    end
  end

  describe "GeneratorError" do
    it "is a StandardError subclass" do
      expect(SupplyChain::Generators::BaseGenerator::GeneratorError.ancestors).to include(StandardError)
    end

    it "can be raised with a message" do
      expect do
        raise SupplyChain::Generators::BaseGenerator::GeneratorError, "Custom error"
      end.to raise_error(SupplyChain::Generators::BaseGenerator::GeneratorError, "Custom error")
    end
  end
end
