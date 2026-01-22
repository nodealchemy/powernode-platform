# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Generators::GemGenerator do
  let(:account) { create(:account) }
  let(:source_path) { Dir.mktmpdir }
  let(:options) { {} }
  let(:generator) { described_class.new(account: account, source_path: source_path, options: options) }

  after do
    FileUtils.remove_entry(source_path) if Dir.exist?(source_path)
  end

  describe "#initialize" do
    it "initializes with required parameters" do
      expect(generator.account).to eq(account)
      expect(generator.source_path).to eq(source_path)
      expect(generator.options).to eq({})
    end

    it "initializes with options hash" do
      opts = { branch: "main", commit_sha: "abc123" }
      gen = described_class.new(account: account, source_path: source_path, options: opts)

      expect(gen.options[:branch]).to eq("main")
      expect(gen.options[:commit_sha]).to eq("abc123")
    end

    it "converts options to indifferent access" do
      opts = { "branch" => "main", commit_sha: "abc123" }
      gen = described_class.new(account: account, source_path: source_path, options: opts)

      expect(gen.options[:branch]).to eq("main")
      expect(gen.options["commit_sha"]).to eq("abc123")
    end
  end

  describe "#generate" do
    context "with Gemfile.lock present" do
      let(:gemfile_lock_content) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              rails (7.0.0)
                actioncable (= 7.0.0)
              actioncable (7.0.0)
                actionpack (= 7.0.0)
              actionpack (7.0.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            rails (~> 7.0)

          BUNDLED WITH
            2.4.0
        LOCKFILE
      end

      before do
        File.write(File.join(source_path, "Gemfile.lock"), gemfile_lock_content)
        File.write(File.join(source_path, "Gemfile"), "gem 'rails', '~> 7.0'")
      end

      it "parses Gemfile.lock when present" do
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

      it "extracts gem names correctly" do
        result = generator.generate

        names = result[:components].map { |c| c[:name] }
        expect(names).to include("rails", "actioncable", "actionpack")
      end

      it "extracts versions correctly" do
        result = generator.generate

        rails_component = result[:components].find { |c| c[:name] == "rails" }
        expect(rails_component[:version]).to eq("7.0.0")
      end
    end

    context "without Gemfile.lock" do
      let(:gemfile_content) do
        <<~GEMFILE
          source 'https://rubygems.org'

          gem 'rails', '~> 7.0'
          gem 'pg', '~> 1.4'
          gem 'rspec', group: :development
        GEMFILE
      end

      before do
        File.write(File.join(source_path, "Gemfile"), gemfile_content)
      end

      it "falls back to parsing Gemfile" do
        result = generator.generate

        expect(result[:components]).to be_an(Array)
        expect(result[:components].length).to eq(3)
      end

      it "extracts gem names from Gemfile" do
        result = generator.generate

        names = result[:components].map { |c| c[:name] }
        expect(names).to include("rails", "pg", "rspec")
      end
    end

    context "with no manifest files" do
      it "returns empty components array" do
        result = generator.generate

        expect(result[:components]).to eq([])
        expect(result[:vulnerabilities]).to eq([])
      end
    end
  end

  describe "#parse_lockfile" do
    describe "standard Gemfile.lock format" do
      let(:lockfile_content) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              rails (7.0.0)
                actioncable (= 7.0.0)
              actioncable (7.0.0)
                actionpack (= 7.0.0)
              actionpack (7.0.0)

          PLATFORMS
            ruby
        LOCKFILE
      end

      it "parses standard Gemfile.lock format" do
        result = generator.parse_lockfile(lockfile_content)

        expect(result[:components]).to be_an(Array)
        expect(result[:components].length).to eq(3)
      end

      it "extracts gem name correctly" do
        result = generator.parse_lockfile(lockfile_content)

        names = result[:components].map { |c| c[:name] }
        expect(names).to contain_exactly("rails", "actioncable", "actionpack")
      end

      it "extracts version correctly" do
        result = generator.parse_lockfile(lockfile_content)

        rails = result[:components].find { |c| c[:name] == "rails" }
        expect(rails[:version]).to eq("7.0.0")
      end
    end

    describe "multiple versions in version spec" do
      let(:lockfile_content) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              multi_version (1.0.0, 1.1.0)
              another_gem (2.3.4)
        LOCKFILE
      end

      it "takes first version when multiple versions present" do
        result = generator.parse_lockfile(lockfile_content)

        multi = result[:components].find { |c| c[:name] == "multi_version" }
        expect(multi[:version]).to eq("1.0.0")
      end
    end

    describe "depth calculation from dependency graph" do
      # In real Gemfile.lock, all gem specs are at 4-space indent.
      # Dependencies are listed at 6-space indent with version constraints.
      # Depth is determined by whether a gem is depended upon by other gems.
      let(:lockfile_content) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              parent_gem (1.0.0)
                child_gem (>= 1.0)
              child_gem (2.0.0)
                grandchild_gem (>= 2.0)
              grandchild_gem (3.0.0)
        LOCKFILE
      end

      it "sets depth 0 for gems not depended on by others (direct)" do
        result = generator.parse_lockfile(lockfile_content)

        parent = result[:components].find { |c| c[:name] == "parent_gem" }
        expect(parent[:depth]).to eq(0)
      end

      it "sets depth 1 for gems depended on by others (transitive)" do
        result = generator.parse_lockfile(lockfile_content)

        child = result[:components].find { |c| c[:name] == "child_gem" }
        expect(child[:depth]).to eq(1)
      end

      it "marks all transitive dependencies with depth 1" do
        result = generator.parse_lockfile(lockfile_content)

        # grandchild_gem is depended on by child_gem, so it's transitive
        grandchild = result[:components].find { |c| c[:name] == "grandchild_gem" }
        expect(grandchild[:depth]).to eq(1)
      end
    end

    describe "dependency_type assignment" do
      # In real Gemfile.lock, dependencies are declared at 6-space indent with constraints
      let(:lockfile_content) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              direct_gem (1.0.0)
                transitive_gem (>= 1.0)
              transitive_gem (2.0.0)
        LOCKFILE
      end

      it "sets dependency_type to direct for gems not depended upon" do
        result = generator.parse_lockfile(lockfile_content)

        direct = result[:components].find { |c| c[:name] == "direct_gem" }
        expect(direct[:dependency_type]).to eq("direct")
      end

      it "sets dependency_type to transitive for gems depended upon by others" do
        result = generator.parse_lockfile(lockfile_content)

        transitive = result[:components].find { |c| c[:name] == "transitive_gem" }
        expect(transitive[:dependency_type]).to eq("transitive")
      end
    end

    describe "platform-specific version handling" do
      let(:lockfile_content) do
        <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              nokogiri (1.15.0)
              nokogiri (1.15.0-x86_64-linux)
              nokogiri (1.15.0-arm64-darwin)
              regular_gem (2.0.0)
        LOCKFILE
      end

      it "skips platform-specific versions containing dash" do
        result = generator.parse_lockfile(lockfile_content)

        nokogiri_entries = result[:components].select { |c| c[:name] == "nokogiri" }
        expect(nokogiri_entries.length).to eq(1)
        expect(nokogiri_entries.first[:version]).to eq("1.15.0")
      end

      it "includes regular versions without platform suffix" do
        result = generator.parse_lockfile(lockfile_content)

        regular = result[:components].find { |c| c[:name] == "regular_gem" }
        expect(regular[:version]).to eq("2.0.0")
      end
    end

    describe "section handling" do
      let(:lockfile_content) do
        <<~LOCKFILE
          GIT
            remote: https://github.com/example/example.git
            revision: abc123
            specs:
              git_gem (0.1.0)

          GEM
            remote: https://rubygems.org/
            specs:
              rubygems_gem (1.0.0)

          PATH
            remote: .
            specs:
              local_gem (0.0.1)

          PLATFORMS
            ruby

          DEPENDENCIES
            git_gem!
            rubygems_gem
            local_gem!
        LOCKFILE
      end

      it "only parses gems from GEM section" do
        result = generator.parse_lockfile(lockfile_content)

        names = result[:components].map { |c| c[:name] }
        expect(names).to include("rubygems_gem")
      end

      it "stops parsing when reaching non-GEM section" do
        result = generator.parse_lockfile(lockfile_content)

        names = result[:components].map { |c| c[:name] }
        # GIT section comes before GEM, so git_gem should not be included
        # PATH section comes after GEM, so local_gem should not be included
        expect(names).not_to include("local_gem")
      end

      it "handles multiple sections correctly" do
        result = generator.parse_lockfile(lockfile_content)

        expect(result[:components].length).to eq(1)
      end
    end

    describe "parse error handling" do
      it "handles parse errors gracefully" do
        allow(Rails.logger).to receive(:error)

        # Create content that will cause the loop to fail
        malformed_content = nil

        # nil content should still return components array
        result = generator.parse_lockfile(malformed_content.to_s)

        expect(result[:components]).to eq([])
      end

      it "returns empty components on error" do
        allow(Rails.logger).to receive(:error)

        # Empty string should not raise
        result = generator.parse_lockfile("")

        expect(result[:components]).to eq([])
      end
    end

    describe "edge cases" do
      it "handles empty GEM section" do
        lockfile_content = <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:

          PLATFORMS
            ruby
        LOCKFILE

        result = generator.parse_lockfile(lockfile_content)

        expect(result[:components]).to eq([])
      end

      it "handles lockfile with only GEM section" do
        lockfile_content = <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              single_gem (1.0.0)
        LOCKFILE

        result = generator.parse_lockfile(lockfile_content)

        expect(result[:components].length).to eq(1)
      end

      it "handles gems with complex version constraints in dependencies" do
        lockfile_content = <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              parent (1.0.0)
                child (>= 2.0, < 3.0)
              child (2.5.0)
        LOCKFILE

        result = generator.parse_lockfile(lockfile_content)

        child = result[:components].find { |c| c[:name] == "child" }
        expect(child[:version]).to eq("2.5.0")
      end
    end
  end

  describe "#parse_gemfile (private method)" do
    describe "gem declaration parsing" do
      it "parses gem declarations with single quotes" do
        gemfile_content = "gem 'rails', '7.0.0'"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].first[:name]).to eq("rails")
      end

      it "parses gem declarations with double quotes" do
        gemfile_content = 'gem "rails", "7.0.0"'
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].first[:name]).to eq("rails")
      end

      it "parses gem declarations with mixed quotes" do
        gemfile_content = <<~GEMFILE
          gem 'single_quoted'
          gem "double_quoted"
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        names = result[:components].map { |c| c[:name] }
        expect(names).to contain_exactly("single_quoted", "double_quoted")
      end
    end

    describe "version extraction" do
      it "extracts version from pessimistic constraint" do
        gemfile_content = "gem 'rails', '~> 7.0'"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rails = result[:components].first
        expect(rails[:version]).to eq("7.0")
      end

      it "extracts version from exact constraint" do
        gemfile_content = "gem 'rails', '= 7.0.0'"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rails = result[:components].first
        expect(rails[:version]).to eq("7.0.0")
      end

      it "extracts version from >= constraint" do
        gemfile_content = "gem 'rails', '>= 7.0.0'"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rails = result[:components].first
        expect(rails[:version]).to eq("7.0.0")
      end

      it "handles missing version" do
        gemfile_content = "gem 'rails'"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rails = result[:components].first
        expect(rails[:version]).to eq("unknown")
      end
    end

    describe "development dependency detection" do
      it "detects :development group" do
        gemfile_content = "gem 'rspec', group: :development"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rspec = result[:components].first
        expect(rspec[:dependency_type]).to eq("dev")
      end

      it "detects development in group array" do
        gemfile_content = "gem 'rspec', group: [:development, :test]"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rspec = result[:components].first
        expect(rspec[:dependency_type]).to eq("dev")
      end

      it "detects :development shorthand" do
        gemfile_content = "gem 'rspec', :development"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rspec = result[:components].first
        expect(rspec[:dependency_type]).to eq("dev")
      end

      it "sets direct for non-development gems" do
        gemfile_content = "gem 'rails', '~> 7.0'"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        rails = result[:components].first
        expect(rails[:dependency_type]).to eq("direct")
      end
    end

    describe "comments and empty lines" do
      it "skips comment lines" do
        gemfile_content = <<~GEMFILE
          # This is a comment
          gem 'rails'
          # Another comment
          gem 'pg'
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].length).to eq(2)
      end

      it "skips empty lines" do
        gemfile_content = <<~GEMFILE
          gem 'rails'

          gem 'pg'

        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].length).to eq(2)
      end

      it "handles inline comments" do
        gemfile_content = "gem 'rails' # inline comment"
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].first[:name]).to eq("rails")
      end
    end

    describe "complex Gemfile scenarios" do
      it "parses Gemfile with source declaration" do
        gemfile_content = <<~GEMFILE
          source 'https://rubygems.org'

          gem 'rails', '~> 7.0'
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].length).to eq(1)
        expect(result[:components].first[:name]).to eq("rails")
      end

      it "parses Gemfile with ruby version" do
        gemfile_content = <<~GEMFILE
          ruby '3.2.0'
          gem 'rails'
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].length).to eq(1)
      end

      it "parses Gemfile with git source" do
        gemfile_content = <<~GEMFILE
          gem 'rails', git: 'https://github.com/rails/rails.git'
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].first[:name]).to eq("rails")
      end

      it "parses Gemfile with path source" do
        gemfile_content = <<~GEMFILE
          gem 'local_gem', path: '../local_gem'
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].first[:name]).to eq("local_gem")
      end

      it "parses Gemfile with require option" do
        gemfile_content = <<~GEMFILE
          gem 'aws-sdk', require: false
        GEMFILE
        File.write(File.join(source_path, "Gemfile"), gemfile_content)

        result = generator.generate

        expect(result[:components].first[:name]).to eq("aws-sdk")
      end
    end
  end

  describe "#ecosystem" do
    it "returns gem" do
      expect(generator.send(:ecosystem)).to eq("gem")
    end
  end

  describe "PURL format" do
    let(:lockfile_content) do
      <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            rails (7.0.0)
      LOCKFILE
    end

    it "returns pkg:gem/name@version format" do
      result = generator.parse_lockfile(lockfile_content)

      rails = result[:components].first
      expect(rails[:purl]).to eq("pkg:gem/rails@7.0.0")
    end

    it "generates correct PURL for all components" do
      lockfile_content = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            nokogiri (1.15.0)
            rake (13.0.6)
      LOCKFILE

      result = generator.parse_lockfile(lockfile_content)

      purls = result[:components].map { |c| c[:purl] }
      expect(purls).to contain_exactly("pkg:gem/nokogiri@1.15.0", "pkg:gem/rake@13.0.6")
    end

    it "handles PURL for gems without version in Gemfile" do
      gemfile_content = "gem 'rails'"
      File.write(File.join(source_path, "Gemfile"), gemfile_content)

      result = generator.generate

      rails = result[:components].first
      expect(rails[:purl]).to eq("pkg:gem/rails")
    end
  end

  describe "component structure" do
    let(:lockfile_content) do
      <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            test_gem (1.2.3)
      LOCKFILE
    end

    it "includes all required component fields" do
      result = generator.parse_lockfile(lockfile_content)

      component = result[:components].first
      expect(component).to have_key(:name)
      expect(component).to have_key(:version)
      expect(component).to have_key(:purl)
      expect(component).to have_key(:ecosystem)
      expect(component).to have_key(:dependency_type)
      expect(component).to have_key(:depth)
    end

    it "sets ecosystem to gem" do
      result = generator.parse_lockfile(lockfile_content)

      component = result[:components].first
      expect(component[:ecosystem]).to eq("gem")
    end
  end

  describe "integration with BaseGenerator" do
    it "inherits from BaseGenerator" do
      expect(described_class.superclass).to eq(SupplyChain::Generators::BaseGenerator)
    end

    it "uses build_component from BaseGenerator" do
      lockfile_content = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            test_gem (1.0.0)
      LOCKFILE

      result = generator.parse_lockfile(lockfile_content)

      component = result[:components].first
      expect(component[:license_spdx_id]).to be_nil
      expect(component[:license_name]).to be_nil
      expect(component[:namespace]).to be_nil
    end
  end

  describe "real-world Gemfile.lock examples" do
    it "parses a realistic Rails application Gemfile.lock" do
      lockfile_content = <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            actioncable (7.1.0)
              actionpack (= 7.1.0)
              activesupport (= 7.1.0)
              nio4r (~> 2.0)
              websocket-driver (>= 0.6.1)
            actionmailbox (7.1.0)
              actionpack (= 7.1.0)
              activejob (= 7.1.0)
              activerecord (= 7.1.0)
              activestorage (= 7.1.0)
              activesupport (= 7.1.0)
              mail (>= 2.7.1)
              net-imap
              net-pop
              net-smtp
            actionpack (7.1.0)
              actionview (= 7.1.0)
              activesupport (= 7.1.0)
              nokogiri (>= 1.8.5)
              rack (>= 2.2.4)
              rack-session (>= 1.0.1)
              rack-test (>= 0.6.3)
              rails-dom-testing (~> 2.2)
              rails-html-sanitizer (~> 1.6)
            activesupport (7.1.0)
              base64
              bigdecimal
              concurrent-ruby (~> 1.0, >= 1.0.2)
              connection_pool (>= 2.2.5)
              drb
              i18n (>= 1.6, < 2)
              minitest (>= 5.1)
              mutex_m
              tzinfo (~> 2.0)
            rails (7.1.0)
              actioncable (= 7.1.0)
              actionmailbox (= 7.1.0)
              actionmailer (= 7.1.0)
              actionpack (= 7.1.0)
              actiontext (= 7.1.0)
              actionview (= 7.1.0)
              activejob (= 7.1.0)
              activemodel (= 7.1.0)
              activerecord (= 7.1.0)
              activestorage (= 7.1.0)
              activesupport (= 7.1.0)
              bundler (>= 1.15.0)
              railties (= 7.1.0)

        PLATFORMS
          ruby
          x86_64-linux

        DEPENDENCIES
          rails (~> 7.1)

        BUNDLED WITH
          2.4.22
      LOCKFILE

      result = generator.parse_lockfile(lockfile_content)

      expect(result[:components].length).to be >= 5

      rails = result[:components].find { |c| c[:name] == "rails" }
      expect(rails[:version]).to eq("7.1.0")
      expect(rails[:dependency_type]).to eq("direct")
      expect(rails[:depth]).to eq(0)

      activesupport = result[:components].find { |c| c[:name] == "activesupport" }
      expect(activesupport[:version]).to eq("7.1.0")
    end
  end
end
