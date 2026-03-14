# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Generators::PipGenerator do
  let(:account) { create(:account) }
  let(:source_path) { Dir.mktmpdir }
  let(:options) { {} }
  let(:generator) { described_class.new(account: account, source_path: source_path, options: options) }

  after do
    FileUtils.remove_entry(source_path) if source_path && Dir.exist?(source_path)
  end

  describe "#initialize" do
    it "initializes with required parameters" do
      expect(generator.account).to eq(account)
      expect(generator.source_path).to eq(source_path)
      expect(generator.options).to eq({})
    end

    it "initializes with options hash" do
      opts = { branch: "main", include_dev: true }
      gen = described_class.new(account: account, source_path: source_path, options: opts)

      expect(gen.options[:branch]).to eq("main")
      expect(gen.options[:include_dev]).to be true
    end

    it "converts options to indifferent access" do
      opts = { "branch" => "main", include_dev: true }
      gen = described_class.new(account: account, source_path: source_path, options: opts)

      expect(gen.options[:branch]).to eq("main")
      expect(gen.options["include_dev"]).to be true
    end
  end

  describe "#generate" do
    context "with Pipfile.lock" do
      let(:pipfile_lock_content) do
        <<~JSON
          {
            "_meta": {
              "hash": {
                "sha256": "abc123"
              },
              "pipfile-spec": 6,
              "requires": {
                "python_version": "3.9"
              }
            },
            "default": {
              "requests": {
                "version": "==2.28.0"
              },
              "urllib3": {
                "version": "==1.26.12"
              }
            },
            "develop": {
              "pytest": {
                "version": "==7.0.0"
              }
            }
          }
        JSON
      end

      before do
        File.write(File.join(source_path, "Pipfile.lock"), pipfile_lock_content)
      end

      it "tries Pipfile.lock first" do
        result = generator.generate

        expect(result[:components]).to be_an(Array)
        expect(result[:components].length).to eq(3)
      end

      it "returns correct structure with components and vulnerabilities" do
        result = generator.generate

        expect(result).to have_key(:components)
        expect(result).to have_key(:vulnerabilities)
        expect(result[:vulnerabilities]).to eq([])
      end

      it "parses default dependencies as direct" do
        result = generator.generate

        requests = result[:components].find { |c| c[:name] == "requests" }
        expect(requests).to be_present
        expect(requests[:dependency_type]).to eq("direct")
        expect(requests[:version]).to eq("2.28.0")
      end

      it "parses develop dependencies as dev" do
        result = generator.generate

        pytest = result[:components].find { |c| c[:name] == "pytest" }
        expect(pytest).to be_present
        expect(pytest[:dependency_type]).to eq("dev")
        expect(pytest[:version]).to eq("7.0.0")
      end

      it "generates correct PURL format" do
        result = generator.generate

        requests = result[:components].find { |c| c[:name] == "requests" }
        expect(requests[:purl]).to eq("pkg:pypi/requests@2.28.0")
      end
    end

    context "fallback to poetry.lock" do
      let(:poetry_lock_content) do
        <<~TOML
          [[package]]
          name = "requests"
          version = "2.28.0"
          category = "main"

          [[package]]
          name = "pytest"
          version = "7.0.0"
          category = "dev"
        TOML
      end

      before do
        File.write(File.join(source_path, "poetry.lock"), poetry_lock_content)
      end

      it "falls back to poetry.lock when Pipfile.lock is missing" do
        result = generator.generate

        expect(result[:components]).to be_an(Array)
        expect(result[:components].length).to eq(2)
      end

      it "parses poetry.lock correctly" do
        result = generator.generate

        requests = result[:components].find { |c| c[:name] == "requests" }
        expect(requests[:version]).to eq("2.28.0")
        expect(requests[:dependency_type]).to eq("direct")
      end
    end

    context "fallback to requirements.txt" do
      let(:requirements_content) do
        <<~TXT
          requests==2.28.0
          pytest>=7.0.0
          flask[async]~=2.0.0
          # This is a comment
          -i https://pypi.org/simple
          --index-url https://pypi.org/simple
        TXT
      end

      before do
        File.write(File.join(source_path, "requirements.txt"), requirements_content)
      end

      it "falls back to requirements.txt when other lockfiles are missing" do
        result = generator.generate

        expect(result[:components]).to be_an(Array)
        expect(result[:components].length).to eq(3)
      end
    end

    context "when no lockfiles exist" do
      it "returns empty components array" do
        result = generator.generate

        expect(result[:components]).to eq([])
        expect(result[:vulnerabilities]).to eq([])
      end
    end

    context "priority order" do
      let(:pipfile_lock_content) do
        <<~JSON
          {
            "_meta": {},
            "default": {
              "from-pipfile": {"version": "==1.0.0"}
            },
            "develop": {}
          }
        JSON
      end

      let(:poetry_lock_content) do
        <<~TOML
          [[package]]
          name = "from-poetry"
          version = "2.0.0"
        TOML
      end

      let(:requirements_content) do
        <<~TXT
          from-requirements==3.0.0
        TXT
      end

      before do
        File.write(File.join(source_path, "Pipfile.lock"), pipfile_lock_content)
        File.write(File.join(source_path, "poetry.lock"), poetry_lock_content)
        File.write(File.join(source_path, "requirements.txt"), requirements_content)
      end

      it "prefers Pipfile.lock over poetry.lock and requirements.txt" do
        result = generator.generate

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("from-pipfile")
      end
    end
  end

  describe "#parse_lockfile" do
    context "detecting Pipfile.lock format" do
      let(:pipfile_lock_content) do
        <<~JSON
          {
            "_meta": {},
            "default": {
              "requests": {"version": "==2.28.0"}
            },
            "develop": {}
          }
        JSON
      end

      it "detects Pipfile.lock format by content markers" do
        result = generator.parse_lockfile(pipfile_lock_content)

        expect(result[:components]).to be_an(Array)
        expect(result[:components].first[:name]).to eq("requests")
      end
    end

    context "detecting poetry.lock format" do
      let(:poetry_lock_content) do
        <<~TOML
          [[package]]
          name = "requests"
          version = "2.28.0"
        TOML
      end

      it "detects poetry.lock format by [[package]] marker" do
        result = generator.parse_lockfile(poetry_lock_content)

        expect(result[:components]).to be_an(Array)
        expect(result[:components].first[:name]).to eq("requests")
      end
    end

    context "defaulting to requirements.txt format" do
      let(:requirements_content) do
        <<~TXT
          requests==2.28.0
        TXT
      end

      it "defaults to requirements.txt parsing when no markers detected" do
        result = generator.parse_lockfile(requirements_content)

        expect(result[:components]).to be_an(Array)
        expect(result[:components].first[:name]).to eq("requests")
      end
    end
  end

  describe "#ecosystem" do
    it "returns pip as ecosystem" do
      expect(generator.send(:ecosystem)).to eq("pip")
    end
  end

  describe "private #parse_pipfile_lock" do
    context "parsing default dependencies" do
      let(:content) do
        <<~JSON
          {
            "_meta": {},
            "default": {
              "requests": {"version": "==2.28.0"},
              "urllib3": {"version": "==1.26.12"}
            },
            "develop": {}
          }
        JSON
      end

      it "parses all default dependencies" do
        components = generator.send(:parse_pipfile_lock, content)

        expect(components.length).to eq(2)
        expect(components.map { |c| c[:name] }).to contain_exactly("requests", "urllib3")
      end

      it "sets dependency_type to direct for default dependencies" do
        components = generator.send(:parse_pipfile_lock, content)

        components.each do |component|
          expect(component[:dependency_type]).to eq("direct")
        end
      end

      it "removes == prefix from version" do
        components = generator.send(:parse_pipfile_lock, content)

        requests = components.find { |c| c[:name] == "requests" }
        expect(requests[:version]).to eq("2.28.0")
      end
    end

    context "parsing develop dependencies" do
      let(:content) do
        <<~JSON
          {
            "_meta": {},
            "default": {},
            "develop": {
              "pytest": {"version": "==7.0.0"},
              "black": {"version": "==22.6.0"}
            }
          }
        JSON
      end

      it "parses all develop dependencies" do
        components = generator.send(:parse_pipfile_lock, content)

        expect(components.length).to eq(2)
        expect(components.map { |c| c[:name] }).to contain_exactly("pytest", "black")
      end

      it "sets dependency_type to dev for develop dependencies" do
        components = generator.send(:parse_pipfile_lock, content)

        components.each do |component|
          expect(component[:dependency_type]).to eq("dev")
        end
      end
    end

    context "normalizing package names in PURL" do
      let(:content) do
        <<~JSON
          {
            "_meta": {},
            "default": {
              "Flask-RESTful": {"version": "==0.3.9"},
              "my_package_name": {"version": "==1.0.0"},
              "some.dotted.package": {"version": "==2.0.0"}
            },
            "develop": {}
          }
        JSON
      end

      it "normalizes package names in PURL to lowercase with hyphens" do
        components = generator.send(:parse_pipfile_lock, content)

        flask = components.find { |c| c[:name] == "Flask-RESTful" }
        expect(flask[:purl]).to eq("pkg:pypi/flask-restful@0.3.9")

        my_pkg = components.find { |c| c[:name] == "my_package_name" }
        expect(my_pkg[:purl]).to eq("pkg:pypi/my-package-name@1.0.0")

        dotted = components.find { |c| c[:name] == "some.dotted.package" }
        expect(dotted[:purl]).to eq("pkg:pypi/some-dotted-package@2.0.0")
      end
    end

    context "handling JSON parse errors" do
      let(:invalid_json) { "{ invalid json content" }

      before do
        allow(Rails.logger).to receive(:error)
      end

      it "returns empty array on JSON parse error" do
        components = generator.send(:parse_pipfile_lock, invalid_json)

        expect(components).to eq([])
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Failed to parse Pipfile.lock/)

        generator.send(:parse_pipfile_lock, invalid_json)
      end
    end

    context "handling missing version" do
      let(:content) do
        <<~JSON
          {
            "_meta": {},
            "default": {
              "requests": {"markers": "python_version >= '3.7'"}
            },
            "develop": {}
          }
        JSON
      end

      it "skips packages without version" do
        components = generator.send(:parse_pipfile_lock, content)

        expect(components).to eq([])
      end
    end

    context "component structure" do
      let(:content) do
        <<~JSON
          {
            "_meta": {},
            "default": {
              "requests": {"version": "==2.28.0"}
            },
            "develop": {}
          }
        JSON
      end

      it "builds component with all required fields" do
        components = generator.send(:parse_pipfile_lock, content)

        expect(components.first).to include(
          name: "requests",
          version: "2.28.0",
          purl: "pkg:pypi/requests@2.28.0",
          ecosystem: "pip",
          dependency_type: "direct",
          depth: 0
        )
      end
    end
  end

  describe "private #parse_poetry_lock" do
    context "parsing [[package]] blocks" do
      let(:content) do
        <<~TOML
          [[package]]
          name = "requests"
          version = "2.28.0"

          [[package]]
          name = "urllib3"
          version = "1.26.12"
        TOML
      end

      it "parses multiple package blocks" do
        components = generator.send(:parse_poetry_lock, content)

        expect(components.length).to eq(2)
        expect(components.map { |c| c[:name] }).to contain_exactly("requests", "urllib3")
      end
    end

    context "extracting name and version" do
      let(:content) do
        <<~TOML
          [[package]]
          name = "requests"
          version = "2.28.0"
          description = "Python HTTP library"
        TOML
      end

      it "extracts name correctly" do
        components = generator.send(:parse_poetry_lock, content)

        expect(components.first[:name]).to eq("requests")
      end

      it "extracts version correctly" do
        components = generator.send(:parse_poetry_lock, content)

        expect(components.first[:version]).to eq("2.28.0")
      end
    end

    context "detecting dev category" do
      let(:content) do
        <<~TOML
          [[package]]
          name = "pytest"
          version = "7.0.0"
          category = "dev"

          [[package]]
          name = "requests"
          version = "2.28.0"
          category = "main"
        TOML
      end

      it "sets dependency_type to dev for dev category" do
        components = generator.send(:parse_poetry_lock, content)

        pytest = components.find { |c| c[:name] == "pytest" }
        expect(pytest[:dependency_type]).to eq("dev")
      end

      it "sets dependency_type to direct for main category" do
        components = generator.send(:parse_poetry_lock, content)

        requests = components.find { |c| c[:name] == "requests" }
        expect(requests[:dependency_type]).to eq("direct")
      end
    end

    context "handling last package without trailing newline" do
      let(:content) do
        "[[package]]\nname = \"requests\"\nversion = \"2.28.0\""
      end

      it "correctly parses last package even without trailing empty line" do
        components = generator.send(:parse_poetry_lock, content)

        expect(components.length).to eq(1)
        expect(components.first[:name]).to eq("requests")
        expect(components.first[:version]).to eq("2.28.0")
      end
    end

    context "handling parse errors" do
      before do
        allow(Rails.logger).to receive(:error)
      end

      it "returns empty array on parse error" do
        # Simulate an error by passing content that causes issues
        allow_any_instance_of(String).to receive(:each_line).and_raise(StandardError.new("test error"))

        components = generator.send(:parse_poetry_lock, "test content")

        expect(components).to eq([])
      end
    end

    context "generating PURL with normalized name" do
      let(:content) do
        <<~TOML
          [[package]]
          name = "Flask-RESTful"
          version = "0.3.9"
        TOML
      end

      it "normalizes package name in PURL" do
        components = generator.send(:parse_poetry_lock, content)

        expect(components.first[:purl]).to eq("pkg:pypi/flask-restful@0.3.9")
      end
    end

    context "component structure" do
      let(:content) do
        <<~TOML
          [[package]]
          name = "requests"
          version = "2.28.0"
          category = "main"
        TOML
      end

      it "builds component with all required fields" do
        components = generator.send(:parse_poetry_lock, content)

        expect(components.first).to include(
          name: "requests",
          version: "2.28.0",
          purl: "pkg:pypi/requests@2.28.0",
          ecosystem: "pip",
          dependency_type: "direct",
          depth: 0
        )
      end
    end

    context "missing required fields" do
      let(:content_missing_name) do
        <<~TOML
          [[package]]
          version = "2.28.0"
        TOML
      end

      let(:content_missing_version) do
        <<~TOML
          [[package]]
          name = "requests"
        TOML
      end

      it "skips packages without name" do
        components = generator.send(:parse_poetry_lock, content_missing_name)

        expect(components).to eq([])
      end

      it "skips packages without version" do
        components = generator.send(:parse_poetry_lock, content_missing_version)

        expect(components).to eq([])
      end
    end
  end

  describe "private #parse_requirements" do
    context "parsing name==version format" do
      let(:content) do
        <<~TXT
          requests==2.28.0
          urllib3==1.26.12
        TXT
      end

      it "parses exact version specifications" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(2)
        requests = components.find { |c| c[:name] == "requests" }
        expect(requests[:version]).to eq("2.28.0")
      end
    end

    context "parsing name>=version format" do
      let(:content) do
        <<~TXT
          requests>=2.28.0
        TXT
      end

      it "parses minimum version specifications" do
        components = generator.send(:parse_requirements, content)

        expect(components.first[:version]).to eq("2.28.0")
      end
    end

    context "parsing name~=version format" do
      let(:content) do
        <<~TXT
          flask~=2.0.0
        TXT
      end

      it "parses compatible release specifications" do
        components = generator.send(:parse_requirements, content)

        expect(components.first[:version]).to eq("2.0.0")
      end
    end

    context "handling package[extras]==version syntax" do
      let(:content) do
        <<~TXT
          flask[async]==2.0.0
          celery[redis,rabbitmq]==5.2.0
        TXT
      end

      it "parses packages with extras correctly" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(2)

        flask = components.find { |c| c[:name] == "flask" }
        expect(flask[:version]).to eq("2.0.0")

        celery = components.find { |c| c[:name] == "celery" }
        expect(celery[:version]).to eq("5.2.0")
      end
    end

    context "skipping comments" do
      let(:content) do
        <<~TXT
          # This is a comment
          requests==2.28.0
          # Another comment
        TXT
      end

      it "ignores comment lines starting with #" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(1)
        expect(components.first[:name]).to eq("requests")
      end
    end

    context "skipping options" do
      let(:content) do
        <<~TXT
          -i https://pypi.org/simple
          --index-url https://pypi.org/simple
          --extra-index-url https://test.pypi.org/simple
          -e git+https://github.com/example/example.git#egg=example
          requests==2.28.0
          -r other-requirements.txt
        TXT
      end

      it "ignores lines starting with -" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(1)
        expect(components.first[:name]).to eq("requests")
      end
    end

    context "handling missing version" do
      let(:content) do
        <<~TXT
          requests
          flask
        TXT
      end

      it "returns unknown for packages without version specifier" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(2)
        components.each do |component|
          expect(component[:version]).to eq("unknown")
        end
      end
    end

    context "handling empty lines" do
      let(:content) do
        <<~TXT
          requests==2.28.0

          flask==2.0.0

        TXT
      end

      it "skips empty lines" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(2)
      end
    end

    context "component structure" do
      let(:content) do
        <<~TXT
          requests==2.28.0
        TXT
      end

      it "builds component with all required fields" do
        components = generator.send(:parse_requirements, content)

        expect(components.first).to include(
          name: "requests",
          version: "2.28.0",
          purl: "pkg:pypi/requests@2.28.0",
          ecosystem: "pip",
          dependency_type: "direct",
          depth: 0
        )
      end
    end

    context "parsing various version operators" do
      let(:content) do
        <<~TXT
          package1==1.0.0
          package2>=2.0.0
          package3<=3.0.0
          package4~=4.0.0
          package5!=5.0.0
          package6>6.0.0
          package7<7.0.0
        TXT
      end

      it "parses all standard version operators" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(7)
        expect(components.map { |c| c[:version] }).to all(match(/^\d+\.\d+\.\d+$/))
      end
    end

    context "handling whitespace" do
      let(:content) do
        <<~TXT
          requests == 2.28.0
          flask>=2.0.0
            urllib3==1.26.12
        TXT
      end

      it "handles whitespace around package specifications" do
        components = generator.send(:parse_requirements, content)

        expect(components.length).to eq(3)
      end
    end
  end

  describe "private #normalize_pypi_name" do
    it "lowercases package names" do
      expect(generator.send(:normalize_pypi_name, "Flask")).to eq("flask")
      expect(generator.send(:normalize_pypi_name, "REQUESTS")).to eq("requests")
    end

    it "replaces underscores with hyphens" do
      expect(generator.send(:normalize_pypi_name, "my_package")).to eq("my-package")
      expect(generator.send(:normalize_pypi_name, "some_long_name")).to eq("some-long-name")
    end

    it "replaces dots with hyphens" do
      expect(generator.send(:normalize_pypi_name, "my.package")).to eq("my-package")
      expect(generator.send(:normalize_pypi_name, "some.dotted.name")).to eq("some-dotted-name")
    end

    it "normalizes multiple consecutive separators to single hyphen" do
      expect(generator.send(:normalize_pypi_name, "my__package")).to eq("my-package")
      expect(generator.send(:normalize_pypi_name, "some..name")).to eq("some-name")
      expect(generator.send(:normalize_pypi_name, "mixed._-name")).to eq("mixed-name")
    end

    it "handles mixed cases and separators" do
      expect(generator.send(:normalize_pypi_name, "Flask_RESTful")).to eq("flask-restful")
      expect(generator.send(:normalize_pypi_name, "My.Package_Name")).to eq("my-package-name")
    end

    it "preserves already normalized names" do
      expect(generator.send(:normalize_pypi_name, "requests")).to eq("requests")
      expect(generator.send(:normalize_pypi_name, "my-package")).to eq("my-package")
    end
  end

  describe "integration tests" do
    context "real-world Pipfile.lock content" do
      let(:content) do
        <<~JSON
          {
            "_meta": {
              "hash": {
                "sha256": "9c7b5ef2b4e4e4f0e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5"
              },
              "pipfile-spec": 6,
              "requires": {
                "python_version": "3.9"
              },
              "sources": [
                {
                  "name": "pypi",
                  "url": "https://pypi.org/simple",
                  "verify_ssl": true
                }
              ]
            },
            "default": {
              "certifi": {
                "hashes": ["sha256:abc123"],
                "version": "==2022.9.24"
              },
              "charset-normalizer": {
                "hashes": ["sha256:def456"],
                "markers": "python_version >= '3.6'",
                "version": "==2.1.1"
              },
              "idna": {
                "hashes": ["sha256:ghi789"],
                "version": "==3.4"
              },
              "requests": {
                "hashes": ["sha256:jkl012"],
                "index": "pypi",
                "version": "==2.28.1"
              }
            },
            "develop": {
              "attrs": {
                "hashes": ["sha256:mno345"],
                "version": "==22.1.0"
              },
              "pytest": {
                "hashes": ["sha256:pqr678"],
                "index": "pypi",
                "version": "==7.1.3"
              }
            }
          }
        JSON
      end

      before do
        File.write(File.join(source_path, "Pipfile.lock"), content)
      end

      it "correctly parses a realistic Pipfile.lock" do
        result = generator.generate

        expect(result[:components].length).to eq(6)

        # Check default dependencies
        requests = result[:components].find { |c| c[:name] == "requests" }
        expect(requests[:version]).to eq("2.28.1")
        expect(requests[:dependency_type]).to eq("direct")

        # Check develop dependencies
        pytest = result[:components].find { |c| c[:name] == "pytest" }
        expect(pytest[:version]).to eq("7.1.3")
        expect(pytest[:dependency_type]).to eq("dev")
      end
    end

    context "real-world poetry.lock content" do
      let(:content) do
        <<~TOML
          [[package]]
          name = "certifi"
          version = "2022.9.24"
          description = "Python package for providing Mozilla's CA Bundle."
          category = "main"
          optional = false
          python-versions = ">=3.6"

          [[package]]
          name = "charset-normalizer"
          version = "2.1.1"
          description = "The Real First Universal Charset Detector."
          category = "main"
          optional = false
          python-versions = ">=3.6.0"

          [[package]]
          name = "pytest"
          version = "7.1.3"
          description = "pytest: simple powerful testing with Python"
          category = "dev"
          optional = false
          python-versions = ">=3.7"
        TOML
      end

      before do
        File.write(File.join(source_path, "poetry.lock"), content)
      end

      it "correctly parses a realistic poetry.lock" do
        result = generator.generate

        expect(result[:components].length).to eq(3)

        certifi = result[:components].find { |c| c[:name] == "certifi" }
        expect(certifi[:version]).to eq("2022.9.24")
        expect(certifi[:dependency_type]).to eq("direct")

        pytest = result[:components].find { |c| c[:name] == "pytest" }
        expect(pytest[:version]).to eq("7.1.3")
        expect(pytest[:dependency_type]).to eq("dev")
      end
    end

    context "real-world requirements.txt content" do
      let(:content) do
        <<~TXT
          # Base requirements
          requests==2.28.1
          urllib3>=1.26.0,<2.0.0
          certifi>=2022.9.24
          charset-normalizer~=2.0.0
          idna>=2.5

          # Development dependencies
          pytest==7.1.3
          black==22.10.0
          flake8>=5.0.0

          # With extras
          celery[redis]==5.2.7
          django[argon2,bcrypt]==4.1.2

          # Index options (should be skipped)
          -i https://pypi.org/simple
          --extra-index-url https://test.pypi.org/simple/

          # Editable installs (should be skipped)
          -e git+https://github.com/user/repo.git#egg=mypackage
        TXT
      end

      before do
        File.write(File.join(source_path, "requirements.txt"), content)
      end

      it "correctly parses a realistic requirements.txt" do
        result = generator.generate

        # Should include packages, not comments or options
        package_names = result[:components].map { |c| c[:name] }
        expect(package_names).to include("requests", "urllib3", "certifi", "pytest", "celery", "django")
        expect(package_names).not_to include("-i", "--extra-index-url")
      end
    end
  end
end
