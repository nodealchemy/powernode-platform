# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/shared_model_controllers_scanner"

# P2 (fc-48) — one model, one serving controller. A model referenced by two or
# more NON-INTERNAL controllers must be listed, with a reason, in the registry
# of the tree that owns the entry (see SharedModelControllersScanner for what
# counts as a reference, an internal controller and the owning tree).
#
# EQUALITY RATCHET, BOTH DIRECTIONS: the scan's shared set must equal the
# merged registries exactly — a newly shared model fails, and so does an
# entry for a model no longer shared (or listed in the wrong tree's
# registry). An entry leaves in the diff that consolidates the model.
#
# EXTENSIONS KEEP THEIR OWN REGISTRY; CORE NAMES NONE OF THEM. Each checked-out
# extension lists its entries in server/spec/fixtures/shared_model_controllers.yml
# inside its own tree (`shared_models:`), where it may also declare its own
# internal controller namespaces (`internal_controller_namespaces:`). Core's
# entries, below, name only core models.
RSpec.describe "shared model controllers registry (P2)" do
  # Core models referenced by two or more non-internal controllers. A reason is
  # a SharedModelControllersScanner::REASONS key or a sentence of its own.
  SHARED_MODEL_CONTROLLERS = {
    "Account" => "tenancy",
    "Account::Delegation" => "lookup",
    "AdminSetting" => "Written by several settings controllers (plan N4: two writers, one setting); consolidating the writers is a P2 offer.",
    "Ai::Agent" => "served_twice",
    "Ai::AgentExecution" => "served_twice",
    "Ai::AgentModelPerformance" => "lookup",
    "Ai::AgentTeam::ReadOnlyCanonical" => "lookup",
    "Ai::CompoundLearning" => "lookup",
    "Ai::Conversation" => "lookup",
    "Ai::Environment" => "lookup",
    "Ai::PersistentContext" => "served_twice",
    "Ai::ProviderCredential" => "served_twice",
    "Ai::RalphLoop" => "lookup",
    "Ai::Skill" => "lookup",
    "Ai::TeamTemplate" => "lookup",
    "ApiKey" => "lookup",
    "AuditLog" => "audit",
    "Devops::ContainerTemplate" => "lookup",
    "Devops::GitRepository" => "lookup",
    "Devops::PipelineRun" => "lookup",
    "FederationPartner" => "lookup",
    "FileManagement::Object" => "served_twice",
    "ImpersonationSession" => "lookup",
    "KnowledgeBase::Article" => "served_twice",
    "McpSession" => "lookup",
    "OauthApplication" => "served_twice",
    "Page" => "served_twice",
    "Platform::ComponentStatus" => "lookup",
    "Role" => "tenancy",
    "SiteSetting" => "lookup",
    "User" => "tenancy",
    "Worker" => "served_twice",
    "WorkerActivity" => "lookup"
  }.freeze

  def resolve_reason(reason)
    SharedModelControllersScanner::REASONS.fetch(reason.to_s, reason.to_s)
  end

  describe "scanner" do
    around do |example|
      Dir.mktmpdir("shared-models-") do |dir|
        @repo = dir
        example.run
      end
    end

    def write(rel, body)
      path = File.join(@repo, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
    end

    def controller(rel, name, body)
      mods = name.split("::")
      klass = mods.pop
      open = mods.map { |m| "module #{m}\n" }.join
      close = "end\n" * mods.size
      write(rel, "#{open}class #{klass} < ApplicationController\n#{body}\nend\n#{close}")
    end

    def shared
      SharedModelControllersScanner.new(@repo).shared_models.transform_values { |cs| cs.map(&:name).sort }
    end

    before do
      write("server/app/models/widget.rb", "class Widget < ApplicationRecord\nend\n")
      write("server/app/models/ai/agent.rb", "module Ai\n  class Agent < ApplicationRecord\n  end\nend\n")
      controller("server/app/controllers/api/v1/widgets_controller.rb", "Api::V1::WidgetsController", "def index; Widget.all; end")
    end

    it "finds nothing when each model has one controller" do
      expect(shared).to eq({})
    end

    it "flags a model two non-internal controllers reference" do
      controller("server/app/controllers/api/v1/reports_controller.rb", "Api::V1::ReportsController", "def show; Widget.find(1); end")

      expect(shared).to eq("Widget" => [ "Api::V1::ReportsController", "Api::V1::WidgetsController" ])
    end

    it "does not count a core Internal:: controller" do
      controller("server/app/controllers/api/v1/internal/widgets_controller.rb", "Api::V1::Internal::WidgetsController",
                 "def index; Widget.all; end")

      expect(shared).to eq({})
    end

    it "does not count a controller in a namespace its extension declares internal" do
      write("extensions/ext/server/spec/fixtures/shared_model_controllers.yml",
            "internal_controller_namespaces:\n  - Api::V1::Ext::WorkerApi\n")
      controller("extensions/ext/server/app/controllers/api/v1/ext/worker_api/sync_controller.rb",
                 "Api::V1::Ext::WorkerApi::SyncController", "def create; ::Widget.first; end")

      expect(shared).to eq({})
    end

    it "only honours an extension's internal namespaces inside that extension's own tree" do
      write("extensions/ext/server/spec/fixtures/shared_model_controllers.yml",
            "internal_controller_namespaces:\n  - Api::V1::Ext::WorkerApi\n")
      controller("server/app/controllers/api/v1/ext/worker_api/sync_controller.rb",
                 "Api::V1::Ext::WorkerApi::SyncController", "def create; Widget.first; end")
      FileUtils.mkdir_p(File.join(@repo, "extensions/ext/server/app"))

      expect(shared.keys).to eq([ "Widget" ])
    end

    it "resolves a short name through the controller's module nesting" do
      controller("server/app/controllers/api/v1/ai/agents_controller.rb", "Api::V1::Ai::AgentsController", "def index; ::Ai::Agent.all; end")
      write("server/app/controllers/ai/runs_controller.rb",
            "module Ai\n  class RunsController < ApplicationController\n    def index; Agent.where(x: 1); end\n  end\nend\n")

      expect(shared).to eq("Ai::Agent" => [ "Ai::RunsController", "Api::V1::Ai::AgentsController" ])
    end

    it "attributes a concern's references to every controller that includes it" do
      write("server/app/controllers/concerns/widget_lookup.rb",
            "module WidgetLookup\n  def widget; Widget.find(params[:id]); end\nend\n")
      controller("server/app/controllers/api/v1/gadgets_controller.rb", "Api::V1::GadgetsController", "include WidgetLookup")

      expect(shared).to eq("Widget" => [ "Api::V1::GadgetsController", "Api::V1::WidgetsController" ])
    end

    it "assigns a core model shared only through a private extension's controller to that extension" do
      FileUtils.mkdir_p(File.join(@repo, "extensions/private/secret/server/app"))
      controller("extensions/private/secret/server/app/controllers/api/v1/secret_controller.rb",
                 "Api::V1::SecretController", "def show; Widget.first; end")
      scanner = SharedModelControllersScanner.new(@repo)

      expect(scanner.owner_tree("Widget").rel).to eq("extensions/private/secret")
    end
    describe "registry merge" do
      it "fails a model listed in two extension registries" do
        write("extensions/a/server/spec/fixtures/shared_model_controllers.yml", "shared_models:\n  Widget: lookup\n")
        write("extensions/b/server/spec/fixtures/shared_model_controllers.yml", "shared_models:\n  Widget: tenancy\n")
        FileUtils.mkdir_p(File.join(@repo, "extensions/a/server/app"))
        FileUtils.mkdir_p(File.join(@repo, "extensions/b/server/app"))

        _, twice = SharedModelControllersScanner.new(@repo).listed_models({})

        expect(twice).to eq([ "Widget (extensions/a, extensions/b)" ])
      end

      it "fails a model listed in core and in an extension registry" do
        write("extensions/a/server/spec/fixtures/shared_model_controllers.yml", "shared_models:\n  Widget: lookup\n")
        FileUtils.mkdir_p(File.join(@repo, "extensions/a/server/app"))

        listed, twice = SharedModelControllersScanner.new(@repo).listed_models("Widget" => "tenancy")

        expect(twice).to eq([ "Widget (server, extensions/a)" ])
        expect(listed["Widget"]).to eq([ "server", "tenancy" ])
      end
    end

    describe "internal_controller_namespaces" do
      def declare(ns)
        write("extensions/ext/server/spec/fixtures/shared_model_controllers.yml",
              "internal_controller_namespaces:\n  - #{ns}\n")
      end

      before { FileUtils.mkdir_p(File.join(@repo, "extensions/ext/server/app")) }

      it "rejects a namespace as broad as Api::V1 or broader" do
        declare("Api::V1")
        controller("extensions/ext/server/app/controllers/api/v1/ext/sync_controller.rb", "Api::V1::Ext::SyncController", "")

        expect(SharedModelControllersScanner.new(@repo).namespace_problems)
          .to eq([ "extensions/ext: internal namespace Api::V1 is Api::V1 or broader" ])
      end

      it "rejects a namespace no controller in its tree lives under (stale)" do
        declare("Api::V1::Ext::Gone")

        expect(SharedModelControllersScanner.new(@repo).namespace_problems)
          .to eq([ "extensions/ext: internal namespace Api::V1::Ext::Gone matches no controller in its tree (stale)" ])
      end

      it "rejects a namespace that also matches a controller in another tree" do
        declare("Api::V1::Shared")
        controller("extensions/ext/server/app/controllers/api/v1/shared/a_controller.rb", "Api::V1::Shared::AController", "")
        controller("server/app/controllers/api/v1/shared/b_controller.rb", "Api::V1::Shared::BController", "")

        expect(SharedModelControllersScanner.new(@repo).namespace_problems)
          .to eq([ "extensions/ext: internal namespace Api::V1::Shared also matches Api::V1::Shared::BController in server" ])
      end

      it "accepts a namespace matching only its own tree's controllers" do
        declare("Api::V1::Ext::WorkerApi")
        controller("extensions/ext/server/app/controllers/api/v1/ext/worker_api/sync_controller.rb",
                   "Api::V1::Ext::WorkerApi::SyncController", "")

        expect(SharedModelControllersScanner.new(@repo).namespace_problems).to eq([])
      end
    end
  end

  describe "the tree" do
    # One scan for both examples: it parses every model and controller.
    before(:all) do
      @scanner = SharedModelControllersScanner.new(File.expand_path("../../..", __dir__))
      @listed, @listed_twice = @scanner.listed_models(SHARED_MODEL_CONTROLLERS)
    end

    let(:scanner) { @scanner }
    let(:listed) { @listed }

    it "lists no model twice (core and registries, or two registries)" do
      expect(@listed_twice).to eq([])
    end

    it "declares only valid internal controller namespaces" do
      expect(scanner.namespace_problems).to eq([])
    end

    it "gives every entry a reason" do
      blank = listed.select { |_, (_, reason)| resolve_reason(reason).strip.empty? }.keys
      expect(blank).to eq([])
    end

    it "lists exactly the shared models, each in its owning tree's registry (equality ratchet)" do
      expected = scanner.shared_models.keys.to_h { |model| [ model, scanner.owner_tree(model).rel ] }
      actual = listed.transform_values(&:first)

      missing = (expected.keys - actual.keys).sort.map { |m| "#{m} (#{expected[m]}: #{scanner.shared_models[m].map(&:name).join(', ')})" }
      stale = (actual.keys - expected.keys).sort
      misplaced = (expected.keys & actual.keys).reject { |m| expected[m] == actual[m] }.sort
                                               .map { |m| "#{m}: listed in #{actual[m]}, belongs in #{expected[m]}" }

      expect(missing: missing, stale: stale, misplaced: misplaced).to eq(missing: [], stale: [], misplaced: [])
    end
  end
end
