# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Generators::NpmGenerator do
  let(:account) { create(:account) }
  let(:source_path) { Dir.mktmpdir }
  let(:options) { {} }
  let(:generator) { described_class.new(account: account, source_path: source_path, options: options) }

  after do
    FileUtils.remove_entry(source_path) if File.exist?(source_path)
  end

  describe "LOCKFILE_NAMES constant" do
    it "defines supported lockfile names in priority order" do
      expect(described_class::LOCKFILE_NAMES).to eq(
        %w[package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml]
      )
    end
  end

  describe "#initialize" do
    it "initializes with required account parameter" do
      expect(generator.account).to eq(account)
    end

    it "initializes with source_path parameter" do
      expect(generator.source_path).to eq(source_path)
    end

    it "initializes with empty options by default" do
      service = described_class.new(account: account, source_path: source_path)
      expect(service.options).to eq({})
    end

    it "initializes with options hash" do
      opts = { include_dev: true, skip_transitive: false }
      service = described_class.new(account: account, source_path: source_path, options: opts)

      expect(service.options[:include_dev]).to eq(true)
      expect(service.options[:skip_transitive]).to eq(false)
    end

    it "converts options to indifferent access" do
      opts = { "include_dev" => true, skip_transitive: false }
      service = described_class.new(account: account, source_path: source_path, options: opts)

      expect(service.options[:include_dev]).to eq(true)
      expect(service.options["skip_transitive"]).to eq(false)
    end
  end

  describe "#generate" do
    context "with lockfile present" do
      let(:package_json) do
        {
          "name" => "test-project",
          "version" => "1.0.0",
          "dependencies" => {
            "lodash" => "^4.17.21"
          }
        }
      end

      let(:lockfile_content) do
        {
          "name" => "test-project",
          "version" => "1.0.0",
          "lockfileVersion" => 3,
          "packages" => {
            "" => { "name" => "test-project", "version" => "1.0.0" },
            "node_modules/lodash" => {
              "version" => "4.17.21",
              "license" => "MIT"
            }
          }
        }
      end

      before do
        File.write(File.join(source_path, "package.json"), package_json.to_json)
        File.write(File.join(source_path, "package-lock.json"), lockfile_content.to_json)
      end

      it "parses lockfile when present" do
        result = generator.generate

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("lodash")
        expect(result[:components].first[:version]).to eq("4.17.21")
      end

      it "returns correct structure with components and vulnerabilities" do
        result = generator.generate

        expect(result).to have_key(:components)
        expect(result).to have_key(:vulnerabilities)
        expect(result[:vulnerabilities]).to eq([])
      end
    end

    context "without lockfile" do
      let(:package_json) do
        {
          "name" => "test-project",
          "version" => "1.0.0",
          "dependencies" => {
            "express" => "^4.18.2",
            "lodash" => "~4.17.21"
          },
          "devDependencies" => {
            "jest" => "^29.0.0"
          }
        }
      end

      before do
        File.write(File.join(source_path, "package.json"), package_json.to_json)
      end

      it "parses package.json when no lockfile present" do
        result = generator.generate

        expect(result[:components].length).to eq(3)
        names = result[:components].map { |c| c[:name] }
        expect(names).to include("express", "lodash", "jest")
      end

      it "cleans version specifiers from package.json" do
        result = generator.generate

        express = result[:components].find { |c| c[:name] == "express" }
        lodash = result[:components].find { |c| c[:name] == "lodash" }

        expect(express[:version]).to eq("4.18.2")
        expect(lodash[:version]).to eq("4.17.21")
      end

      it "sets devDependencies as dev type" do
        result = generator.generate

        jest = result[:components].find { |c| c[:name] == "jest" }
        expect(jest[:dependency_type]).to eq("dev")
      end
    end

    context "with no manifest or lockfile" do
      it "returns empty components array" do
        result = generator.generate

        expect(result[:components]).to eq([])
        expect(result[:vulnerabilities]).to eq([])
      end
    end

    context "lockfile priority" do
      let(:package_json) { { "name" => "test", "dependencies" => {} } }

      before do
        File.write(File.join(source_path, "package.json"), package_json.to_json)
      end

      it "reads package-lock.json first" do
        lockfile = { "lockfileVersion" => 3, "packages" => { "node_modules/pkg1" => { "version" => "1.0.0" } } }
        File.write(File.join(source_path, "package-lock.json"), lockfile.to_json)
        File.write(File.join(source_path, "yarn.lock"), "invalid-content")

        result = generator.generate

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("pkg1")
      end

      it "reads npm-shrinkwrap.json when package-lock.json is absent" do
        lockfile = { "lockfileVersion" => 3, "packages" => { "node_modules/pkg2" => { "version" => "2.0.0" } } }
        File.write(File.join(source_path, "npm-shrinkwrap.json"), lockfile.to_json)

        result = generator.generate

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("pkg2")
      end
    end
  end

  describe "#parse_lockfile" do
    context "npm v2/v3 format (packages key)" do
      let(:lockfile_content) do
        {
          "name" => "test-project",
          "lockfileVersion" => 3,
          "packages" => {
            "" => { "name" => "test-project", "version" => "1.0.0" },
            "node_modules/express" => {
              "version" => "4.18.2",
              "license" => "MIT"
            },
            "node_modules/lodash" => {
              "version" => "4.17.21",
              "license" => "MIT",
              "dev" => true
            }
          }
        }
      end

      it "parses components from packages key" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        expect(result[:components].length).to eq(2)
      end

      it "extracts name, version, and license" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        express = result[:components].find { |c| c[:name] == "express" }
        expect(express[:version]).to eq("4.18.2")
        expect(express[:license_spdx_id]).to eq("MIT")
      end

      it "sets correct dependency_type for dev packages" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        lodash = result[:components].find { |c| c[:name] == "lodash" }
        expect(lodash[:dependency_type]).to eq("dev")
      end

      it "sets correct dependency_type for non-dev packages" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        express = result[:components].find { |c| c[:name] == "express" }
        expect(express[:dependency_type]).to eq("direct")
      end

      it "calculates depth correctly from path" do
        lockfile = {
          "packages" => {
            "node_modules/express" => { "version" => "4.18.2" },
            "node_modules/express/node_modules/accepts" => { "version" => "1.3.8" }
          }
        }

        result = generator.parse_lockfile(lockfile.to_json)

        express = result[:components].find { |c| c[:name] == "express" }
        accepts = result[:components].find { |c| c[:name] == "accepts" }

        expect(express[:depth]).to eq(1)
        expect(accepts[:depth]).to eq(3)
      end

      it "skips root package (empty path)" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        root = result[:components].find { |c| c[:name] == "test-project" }
        expect(root).to be_nil
      end

      it "skips linked packages" do
        lockfile = {
          "packages" => {
            "node_modules/local-pkg" => {
              "link" => true
            },
            "node_modules/real-pkg" => {
              "version" => "1.0.0"
            }
          }
        }

        result = generator.parse_lockfile(lockfile.to_json)

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("real-pkg")
      end

      it "skips packages without version" do
        lockfile = {
          "packages" => {
            "node_modules/no-version" => {
              "license" => "MIT"
            },
            "node_modules/with-version" => {
              "version" => "1.0.0"
            }
          }
        }

        result = generator.parse_lockfile(lockfile.to_json)

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("with-version")
      end
    end

    context "npm v1 format (dependencies key)" do
      let(:lockfile_content) do
        {
          "name" => "test-project",
          "lockfileVersion" => 1,
          "dependencies" => {
            "express" => {
              "version" => "4.18.2",
              "dev" => false,
              "dependencies" => {
                "accepts" => {
                  "version" => "1.3.8"
                }
              }
            },
            "jest" => {
              "version" => "29.0.0",
              "dev" => true
            }
          }
        }
      end

      it "parses components from dependencies key" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        expect(result[:components].length).to eq(3)
      end

      it "recursively parses nested dependencies" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        accepts = result[:components].find { |c| c[:name] == "accepts" }
        expect(accepts).not_to be_nil
        expect(accepts[:version]).to eq("1.3.8")
      end

      it "sets correct depth for nested dependencies" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        express = result[:components].find { |c| c[:name] == "express" }
        accepts = result[:components].find { |c| c[:name] == "accepts" }

        expect(express[:depth]).to eq(0)
        expect(accepts[:depth]).to eq(1)
      end

      it "sets transitive dependency_type for nested dependencies" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        accepts = result[:components].find { |c| c[:name] == "accepts" }
        expect(accepts[:dependency_type]).to eq("transitive")
      end

      it "sets dev dependency_type for dev packages" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        jest = result[:components].find { |c| c[:name] == "jest" }
        expect(jest[:dependency_type]).to eq("dev")
      end
    end

    context "scoped packages" do
      let(:lockfile_content) do
        {
          "packages" => {
            "node_modules/@babel/core" => {
              "version" => "7.23.0",
              "license" => "MIT"
            },
            "node_modules/@types/node" => {
              "version" => "20.8.0",
              "license" => "MIT",
              "dev" => true
            }
          }
        }
      end

      it "extracts scoped package names correctly" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        babel = result[:components].find { |c| c[:name] == "@babel/core" }
        types = result[:components].find { |c| c[:name] == "@types/node" }

        expect(babel).not_to be_nil
        expect(types).not_to be_nil
      end

      it "builds correct purl for scoped packages" do
        result = generator.parse_lockfile(lockfile_content.to_json)

        babel = result[:components].find { |c| c[:name] == "@babel/core" }
        expect(babel[:purl]).to eq("pkg:npm/babel/core@7.23.0")
      end
    end

    context "JSON parse errors" do
      before do
        allow(Rails.logger).to receive(:error)
      end

      it "handles invalid JSON gracefully" do
        result = generator.parse_lockfile("not valid json {")

        expect(result[:components]).to eq([])
      end

      it "logs error on JSON parse failure" do
        generator.parse_lockfile("invalid json")

        expect(Rails.logger).to have_received(:error).with(/Failed to parse lockfile/)
      end
    end
  end

  describe "#parse_manifest (via generate)" do
    context "parsing different dependency types" do
      let(:package_json) do
        {
          "name" => "test-project",
          "dependencies" => {
            "express" => "4.18.2"
          },
          "devDependencies" => {
            "jest" => "29.0.0"
          },
          "peerDependencies" => {
            "react" => "18.2.0"
          },
          "optionalDependencies" => {
            "fsevents" => "2.3.3"
          }
        }
      end

      before do
        File.write(File.join(source_path, "package.json"), package_json.to_json)
      end

      it "parses dependencies" do
        result = generator.generate

        express = result[:components].find { |c| c[:name] == "express" }
        expect(express[:version]).to eq("4.18.2")
        expect(express[:dependency_type]).to eq("direct")
      end

      it "parses devDependencies as dev type" do
        result = generator.generate

        jest = result[:components].find { |c| c[:name] == "jest" }
        expect(jest[:dependency_type]).to eq("dev")
      end

      it "parses peerDependencies as direct type" do
        result = generator.generate

        react = result[:components].find { |c| c[:name] == "react" }
        expect(react[:dependency_type]).to eq("direct")
      end

      it "parses optionalDependencies as direct type" do
        result = generator.generate

        fsevents = result[:components].find { |c| c[:name] == "fsevents" }
        expect(fsevents[:dependency_type]).to eq("direct")
      end

      it "sets depth to 0 for all manifest dependencies" do
        result = generator.generate

        result[:components].each do |component|
          expect(component[:depth]).to eq(0)
        end
      end
    end
  end

  describe "#build_npm_purl (via parse_lockfile)" do
    it "builds correct purl for regular package" do
      lockfile = {
        "packages" => {
          "node_modules/lodash" => { "version" => "4.17.21" }
        }
      }

      result = generator.parse_lockfile(lockfile.to_json)

      expect(result[:components].first[:purl]).to eq("pkg:npm/lodash@4.17.21")
    end

    it "builds correct purl for scoped package" do
      lockfile = {
        "packages" => {
          "node_modules/@scope/package" => { "version" => "1.0.0" }
        }
      }

      result = generator.parse_lockfile(lockfile.to_json)

      expect(result[:components].first[:purl]).to eq("pkg:npm/scope/package@1.0.0")
    end

    it "removes @ from scope in purl" do
      lockfile = {
        "packages" => {
          "node_modules/@angular/core" => { "version" => "17.0.0" }
        }
      }

      result = generator.parse_lockfile(lockfile.to_json)

      expect(result[:components].first[:purl]).to eq("pkg:npm/angular/core@17.0.0")
      expect(result[:components].first[:purl]).not_to include("@angular")
    end
  end

  describe "#clean_version (via generate without lockfile)" do
    def test_version_cleaning(version_spec, expected)
      package_json = { "dependencies" => { "pkg" => version_spec } }
      File.write(File.join(source_path, "package.json"), package_json.to_json)

      result = generator.generate
      expect(result[:components].first[:version]).to eq(expected)
    end

    it "removes ^ prefix" do
      test_version_cleaning("^1.2.3", "1.2.3")
    end

    it "removes ~ prefix" do
      test_version_cleaning("~1.2.3", "1.2.3")
    end

    it "removes >= prefix" do
      test_version_cleaning(">=1.2.3", "1.2.3")
    end

    it "removes > prefix" do
      test_version_cleaning(">1.2.3", "1.2.3")
    end

    it "removes <= prefix" do
      test_version_cleaning("<=1.2.3", "1.2.3")
    end

    it "removes < prefix" do
      test_version_cleaning("<1.2.3", "1.2.3")
    end

    it "handles version ranges (takes first version)" do
      test_version_cleaning(">=1.2.3 <2.0.0", "1.2.3")
    end

    it "handles exact version (no change)" do
      test_version_cleaning("1.2.3", "1.2.3")
    end

    it "handles combined operators" do
      test_version_cleaning("^~1.2.3", "1.2.3")
    end
  end

  describe "#normalize_license (via parse_lockfile)" do
    def test_license_normalization(license_value, expected)
      lockfile = {
        "packages" => {
          "node_modules/pkg" => {
            "version" => "1.0.0",
            "license" => license_value
          }
        }
      }

      result = generator.parse_lockfile(lockfile.to_json)
      expect(result[:components].first[:license_spdx_id]).to eq(expected)
    end

    it "maps MIT to MIT" do
      test_license_normalization("MIT", "MIT")
    end

    it "maps ISC to ISC" do
      test_license_normalization("ISC", "ISC")
    end

    it "maps Apache-2.0 to Apache-2.0" do
      test_license_normalization("Apache-2.0", "Apache-2.0")
    end

    it "maps 'Apache 2.0' to Apache-2.0" do
      test_license_normalization("Apache 2.0", "Apache-2.0")
    end

    it "maps BSD-2-Clause to BSD-2-Clause" do
      test_license_normalization("BSD-2-Clause", "BSD-2-Clause")
    end

    it "maps BSD-3-Clause to BSD-3-Clause" do
      test_license_normalization("BSD-3-Clause", "BSD-3-Clause")
    end

    it "maps GPL-3.0 to GPL-3.0-only" do
      test_license_normalization("GPL-3.0", "GPL-3.0-only")
    end

    it "maps GPL-2.0 to GPL-2.0-only" do
      test_license_normalization("GPL-2.0", "GPL-2.0-only")
    end

    it "maps LGPL-3.0 to LGPL-3.0-only" do
      test_license_normalization("LGPL-3.0", "LGPL-3.0-only")
    end

    it "maps LGPL-2.1 to LGPL-2.1-only" do
      test_license_normalization("LGPL-2.1", "LGPL-2.1-only")
    end

    it "maps MPL-2.0 to MPL-2.0" do
      test_license_normalization("MPL-2.0", "MPL-2.0")
    end

    it "maps Unlicense to Unlicense" do
      test_license_normalization("Unlicense", "Unlicense")
    end

    it "maps CC0-1.0 to CC0-1.0" do
      test_license_normalization("CC0-1.0", "CC0-1.0")
    end

    it "maps WTFPL to WTFPL" do
      test_license_normalization("WTFPL", "WTFPL")
    end

    it "returns unknown licenses as-is" do
      test_license_normalization("Proprietary", "Proprietary")
    end

    it "returns nil for nil license" do
      lockfile = {
        "packages" => {
          "node_modules/pkg" => { "version" => "1.0.0" }
        }
      }

      result = generator.parse_lockfile(lockfile.to_json)
      expect(result[:components].first[:license_spdx_id]).to be_nil
    end

    it "handles license object with type key" do
      lockfile = {
        "packages" => {
          "node_modules/pkg" => {
            "version" => "1.0.0",
            "license" => { "type" => "MIT" }
          }
        }
      }

      result = generator.parse_lockfile(lockfile.to_json)
      expect(result[:components].first[:license_spdx_id]).to eq("MIT")
    end
  end

  describe "#ecosystem" do
    it "returns 'npm'" do
      expect(generator.send(:ecosystem)).to eq("npm")
    end
  end

  describe "#extract_package_name" do
    it "extracts name from simple node_modules path" do
      expect(generator.send(:extract_package_name, "node_modules/lodash")).to eq("lodash")
    end

    it "extracts name from scoped package path" do
      expect(generator.send(:extract_package_name, "node_modules/@babel/core")).to eq("@babel/core")
    end

    it "extracts name from nested node_modules path" do
      expect(generator.send(:extract_package_name, "node_modules/express/node_modules/accepts")).to eq("accepts")
    end

    it "extracts scoped name from deeply nested path" do
      expect(generator.send(:extract_package_name, "node_modules/pkg/node_modules/@types/node")).to eq("@types/node")
    end

    it "returns nil for empty path" do
      expect(generator.send(:extract_package_name, "")).to be_nil
    end
  end

  describe "integration scenarios" do
    context "real-world package-lock.json v3 structure" do
      let(:lockfile_content) do
        {
          "name" => "my-app",
          "version" => "1.0.0",
          "lockfileVersion" => 3,
          "requires" => true,
          "packages" => {
            "" => {
              "name" => "my-app",
              "version" => "1.0.0",
              "dependencies" => {
                "express" => "^4.18.2"
              },
              "devDependencies" => {
                "typescript" => "^5.0.0"
              }
            },
            "node_modules/express" => {
              "version" => "4.18.2",
              "license" => "MIT",
              "dependencies" => {
                "accepts" => "~1.3.8"
              }
            },
            "node_modules/accepts" => {
              "version" => "1.3.8",
              "license" => "MIT"
            },
            "node_modules/typescript" => {
              "version" => "5.3.2",
              "dev" => true,
              "license" => "Apache-2.0"
            }
          }
        }
      end

      before do
        File.write(File.join(source_path, "package.json"), { "name" => "my-app" }.to_json)
        File.write(File.join(source_path, "package-lock.json"), lockfile_content.to_json)
      end

      it "parses all components correctly" do
        result = generator.generate

        expect(result[:components].length).to eq(3)

        express = result[:components].find { |c| c[:name] == "express" }
        accepts = result[:components].find { |c| c[:name] == "accepts" }
        typescript = result[:components].find { |c| c[:name] == "typescript" }

        expect(express[:version]).to eq("4.18.2")
        expect(express[:license_spdx_id]).to eq("MIT")
        expect(express[:dependency_type]).to eq("direct")

        expect(accepts[:version]).to eq("1.3.8")
        expect(accepts[:dependency_type]).to eq("direct")

        expect(typescript[:version]).to eq("5.3.2")
        expect(typescript[:dependency_type]).to eq("dev")
        expect(typescript[:license_spdx_id]).to eq("Apache-2.0")
      end
    end

    context "package.json with all dependency types" do
      let(:package_json) do
        {
          "name" => "full-example",
          "version" => "2.0.0",
          "dependencies" => {
            "react" => "^18.2.0",
            "@reduxjs/toolkit" => "^1.9.5"
          },
          "devDependencies" => {
            "typescript" => "^5.0.0",
            "@types/react" => "^18.0.0"
          },
          "peerDependencies" => {
            "react-dom" => ">=18.0.0"
          },
          "optionalDependencies" => {
            "fsevents" => "~2.3.0"
          }
        }
      end

      before do
        File.write(File.join(source_path, "package.json"), package_json.to_json)
      end

      it "parses all dependency types with correct metadata" do
        result = generator.generate

        expect(result[:components].length).to eq(6)

        react = result[:components].find { |c| c[:name] == "react" }
        expect(react[:version]).to eq("18.2.0")
        expect(react[:purl]).to eq("pkg:npm/react@18.2.0")
        expect(react[:dependency_type]).to eq("direct")

        redux = result[:components].find { |c| c[:name] == "@reduxjs/toolkit" }
        expect(redux[:purl]).to eq("pkg:npm/reduxjs/toolkit@1.9.5")

        ts = result[:components].find { |c| c[:name] == "typescript" }
        expect(ts[:dependency_type]).to eq("dev")

        types_react = result[:components].find { |c| c[:name] == "@types/react" }
        expect(types_react[:dependency_type]).to eq("dev")
        expect(types_react[:purl]).to eq("pkg:npm/types/react@18.0.0")

        react_dom = result[:components].find { |c| c[:name] == "react-dom" }
        expect(react_dom[:version]).to eq("18.0.0")
        expect(react_dom[:dependency_type]).to eq("direct")

        fsevents = result[:components].find { |c| c[:name] == "fsevents" }
        expect(fsevents[:version]).to eq("2.3.0")
      end
    end

    context "npm v1 lockfile with nested dependencies" do
      let(:lockfile_content) do
        {
          "name" => "legacy-app",
          "lockfileVersion" => 1,
          "dependencies" => {
            "express" => {
              "version" => "4.17.1",
              "dependencies" => {
                "body-parser" => {
                  "version" => "1.19.0",
                  "dependencies" => {
                    "debug" => {
                      "version" => "2.6.9"
                    }
                  }
                }
              }
            }
          }
        }
      end

      before do
        File.write(File.join(source_path, "package.json"), { "name" => "legacy-app" }.to_json)
        File.write(File.join(source_path, "package-lock.json"), lockfile_content.to_json)
      end

      it "parses nested dependencies with correct depth" do
        result = generator.generate

        express = result[:components].find { |c| c[:name] == "express" }
        body_parser = result[:components].find { |c| c[:name] == "body-parser" }
        debug = result[:components].find { |c| c[:name] == "debug" }

        expect(express[:depth]).to eq(0)
        expect(express[:dependency_type]).to eq("direct")

        expect(body_parser[:depth]).to eq(1)
        expect(body_parser[:dependency_type]).to eq("transitive")

        expect(debug[:depth]).to eq(2)
        expect(debug[:dependency_type]).to eq("transitive")
      end
    end
  end
end
