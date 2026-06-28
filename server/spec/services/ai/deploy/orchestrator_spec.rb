# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "open3"
require "fileutils"

RSpec.describe Ai::Deploy::Orchestrator do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:target) do
    Ai::Deploy::Target.new(kind: :project, environment: "production", config: { "method" => "workload" })
  end

  let(:healthy_method) do
    Class.new(Ai::Deploy::Method) do
      def self.key = :workload
      def self.available? = true

      def deploy!(target:, ref:, dry_run: true)
        dry_run ? Ai::Deploy::Result.dry(commands: ["deploy #{ref}"]) : Ai::Deploy::Result.ok("deployed #{ref}")
      end

      def verify_health(target:, deploy_run:)
        Ai::Deploy::Result.ok("healthy")
      end
    end
  end

  let(:unhealthy_method) do
    Class.new(Ai::Deploy::Method) do
      def self.key = :workload
      def self.available? = true

      def deploy!(target:, ref:, dry_run: true)
        Ai::Deploy::Result.ok("deployed #{ref}")
      end

      def verify_health(target:, deploy_run:)
        Ai::Deploy::Result.failure("503 from /up")
      end

      def rollback!(target:, deploy_run:)
        Ai::Deploy::Result.new(status: :rolled_back, detail: "reverted to prior")
      end
    end
  end

  around do |example|
    saved = Ai::Deploy::MethodRegistry::CORE_METHODS.dup
    Ai::Deploy::MethodRegistry.reset_core!
    example.run
    Ai::Deploy::MethodRegistry.reset_core!
    saved.each_value { |klass| Ai::Deploy::MethodRegistry.register(klass) }
  end

  # Isolate from whichever extensions are installed (the system extension contributes a
  # :kubernetes method via the provider seam) so the registry resolves only what each test
  # explicitly registers.
  before { allow(Ai::Deploy::MethodRegistry).to receive(:extension_methods).and_return({}) }

  def orchestrator(repo: nil)
    described_class.new(account: account, user: user, repository_path: repo)
  end

  it "dry-runs by default: records the would-run commands, no health/rollback" do
    Ai::Deploy::MethodRegistry.register(healthy_method)
    run = orchestrator.deploy(target: target, ref: "abc123", base_ref: nil, dry_run: true)
    expect(run.status).to eq("dry_run")
    expect(run.dry_run).to be true
    expect(run.commands).to eq(["deploy abc123"])
    expect(AuditLog.where(action: "deploy.dry_run", resource_id: run.id)).to exist
  end

  it "real deploy that stays healthy → succeeded" do
    Ai::Deploy::MethodRegistry.register(healthy_method)
    run = orchestrator.deploy(target: target, ref: "abc", base_ref: nil, dry_run: false)
    expect(run.status).to eq("succeeded")
    expect(AuditLog.where(action: "deploy.succeeded", resource_id: run.id)).to exist
  end

  it "real deploy that fails health → auto-rolls-back" do
    Ai::Deploy::MethodRegistry.register(unhealthy_method)
    run = orchestrator.deploy(target: target, ref: "abc", base_ref: nil, dry_run: false)
    expect(run.status).to eq("rolled_back")
    expect(run.error_message).to match(/health failed/)
    expect(run.metadata["rollback"]).to be_present
    expect(AuditLog.where(action: "deploy.rolled_back", resource_id: run.id)).to exist
  end

  it "skips when the kill-switch is active (method never runs)" do
    Ai::Deploy::MethodRegistry.register(healthy_method)
    account.update!(ai_suspended: true)
    run = orchestrator.deploy(target: target, ref: "abc", dry_run: false)
    expect(run.status).to eq("skipped")
  end

  it "blocks when no deploy method is available" do
    # registry intentionally empty
    run = orchestrator.deploy(target: Ai::Deploy::Target.new(kind: :project), ref: "abc", dry_run: true)
    expect(run.status).to eq("blocked")
    expect(run.error_message).to match(/no available deploy method/)
  end

  context "migration-safety gate" do
    attr_reader :repo

    def git!(*args)
      out, err, st = Open3.capture3("git", *args, chdir: repo)
      raise "git #{args.join(' ')}: #{err}" unless st.success?

      out.strip
    end

    around do |example|
      Dir.mktmpdir do |root|
        @repo = root
        Open3.capture3("git", "-c", "init.defaultBranch=main", "init", root)
        git!("config", "user.email", "t@example.com"); git!("config", "user.name", "T")
        FileUtils.mkdir_p(File.join(root, "server/db/migrate"))
        File.write(File.join(root, "base.txt"), "x\n"); git!("add", "."); git!("commit", "-m", "init")
        git!("checkout", "-b", "feature")
        File.write(File.join(root, "server/db/migrate/20260101000009_drop_things.rb"), <<~RB)
          class DropThings < ActiveRecord::Migration[8.0]
            def change
              drop_table :things
            end
          end
        RB
        git!("add", "."); git!("commit", "-m", "irreversible migration")
        git!("checkout", "main")
        example.run
      end
    end

    it "blocks a real deploy carrying an irreversible migration" do
      Ai::Deploy::MethodRegistry.register(healthy_method)
      run = orchestrator(repo: repo).deploy(target: target, ref: "feature", base_ref: "main", dry_run: false)
      expect(run.status).to eq("blocked")
      expect(run.error_message).to match(/migration-safety/)
      expect(run.metadata.dig("migration_safety", "irreversible")).to be_present
    end

    it "allows it when allow_irreversible is set" do
      Ai::Deploy::MethodRegistry.register(healthy_method)
      run = orchestrator(repo: repo).deploy(target: target, ref: "feature", base_ref: "main",
                                            dry_run: false, allow_irreversible: true)
      expect(run.status).to eq("succeeded")
    end
  end
end
