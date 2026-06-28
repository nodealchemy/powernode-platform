# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "open3"
require "fileutils"

# Foundation of the Ai::Deploy seam: Result/Target value objects, the MethodRegistry
# (core + extension-provider resolution, default-order selection), and the deterministic
# MigrationSafetyChecker. No Orchestrator/DB dependency yet — methods are added on top.
RSpec.describe "Ai::Deploy foundation" do
  describe Ai::Deploy::Result do
    it "builds status variants and rejects unknown statuses" do
      expect(Ai::Deploy::Result.ok("done")).to be_succeeded
      expect(Ai::Deploy::Result.failure("nope")).to be_failed
      dry = Ai::Deploy::Result.dry(commands: ["systemctl restart powernode-backend@default"])
      expect(dry).to be_dry_run
      expect(dry.commands).to eq(["systemctl restart powernode-backend@default"])
      expect { Ai::Deploy::Result.new(status: :bogus) }.to raise_error(ArgumentError)
    end
  end

  describe Ai::Deploy::Target do
    it "validates kind, exposes predicates + explicit method override" do
      t = Ai::Deploy::Target.new(kind: :project, environment: "production", config: { method: "workload" })
      expect(t).to be_project
      expect(t).to be_production
      expect(t.method_key).to eq(:workload)
      expect(Ai::Deploy::Target.new(kind: :platform_self)).to be_platform_self
      expect { Ai::Deploy::Target.new(kind: :bogus) }.to raise_error(ArgumentError)
    end
  end

  describe Ai::Deploy::MethodRegistry do
    let(:workload_method) do
      Class.new(Ai::Deploy::Method) do
        def self.key = :workload
        def self.available? = true
      end
    end
    let(:unavailable_docker) do
      Class.new(Ai::Deploy::Method) do
        def self.key = :docker
        def self.available? = false
      end
    end

    around do |ex|
      saved = described_class::CORE_METHODS.dup
      described_class.reset_core!
      ex.run
      described_class.reset_core!
      saved.each_value { |klass| described_class.register(klass) }
    end

    # Isolate the core-registry resolution tests from whichever extensions happen to be
    # installed (the public system extension contributes :kubernetes via the provider seam).
    before { allow(described_class).to receive(:extension_methods).and_return({}) }

    it "resolves by default order (first available) and by explicit override" do
      described_class.register(workload_method)
      described_class.register(unavailable_docker)

      project = Ai::Deploy::Target.new(kind: :project)
      expect(described_class.resolve(project)).to eq(workload_method) # workload first + available

      explicit_unavailable = Ai::Deploy::Target.new(kind: :project, config: { method: "docker" })
      expect(described_class.resolve(explicit_unavailable)).to be_nil  # docker registered but unavailable

      expect(described_class.available.keys).to contain_exactly(:workload)
    end

    it "merges only core methods when no extension provider is present" do
      described_class.register(workload_method)
      expect(described_class.all.keys).to contain_exactly(:workload)
    end
  end

  describe "#{Ai::Deploy::MethodRegistry} extension provider seam" do
    let(:fake_method) { Class.new(Ai::Deploy::Method) { def self.key = :ext_method } }

    it "merges extension-provided methods resolved via ExtensionRegistry (core never names them)" do
      provider = Module.new
      methods_map = { ext_method: fake_method }
      provider.define_singleton_method(:deploy_methods) { methods_map }
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:deploy_method_providers).and_return(provider)

      expect(Ai::Deploy::MethodRegistry.extension_methods).to eq(ext_method: fake_method)
      expect(Ai::Deploy::MethodRegistry.all.keys).to include(:ext_method)
    end
  end

  describe Ai::Deploy::MigrationSafetyChecker do
    attr_reader :repo

    def git!(*args)
      out, err, st = Open3.capture3("git", *args, chdir: repo)
      raise "git #{args.join(' ')}: #{err}" unless st.success?

      out.strip
    end

    around do |ex|
      Dir.mktmpdir do |root|
        @repo = root
        Open3.capture3("git", "-c", "init.defaultBranch=main", "init", root)
        git!("config", "user.email", "t@example.com")
        git!("config", "user.name", "T")
        FileUtils.mkdir_p(File.join(root, "server/db/migrate"))
        File.write(File.join(root, "base.txt"), "x\n")
        git!("add", "."); git!("commit", "-m", "init")

        git!("checkout", "-b", "feature")
        File.write(File.join(root, "server/db/migrate/20260101000001_add_col.rb"), <<~RB)
          class AddCol < ActiveRecord::Migration[8.0]
            def change
              add_column :things, :name, :string
            end
          end
        RB
        File.write(File.join(root, "server/db/migrate/20260101000002_drop_things.rb"), <<~RB)
          class DropThings < ActiveRecord::Migration[8.0]
            def change
              drop_table :things
            end
          end
        RB
        git!("add", "."); git!("commit", "-m", "migrations")
        git!("checkout", "main")
        ex.run
      end
    end

    it "flags only the irreversible added migration; override forces safe" do
      checker = described_class.new(repository_path: repo)
      report = checker.check(base_ref: "main", target_ref: "feature")

      expect(report.added.size).to eq(2)
      expect(report.irreversible.map { |p| File.basename(p) }).to eq(["20260101000002_drop_things.rb"])
      expect(report).not_to be_safe
      expect(report.reasons.join).to match(/irreversible/)

      expect(checker.check(base_ref: "main", target_ref: "feature", allow_irreversible: true)).to be_safe
    end

    it "is safe when no migrations were added" do
      report = described_class.new(repository_path: repo).check(base_ref: "main", target_ref: "main")
      expect(report.added).to be_empty
      expect(report).to be_safe
    end
  end
end
