# frozen_string_literal: true

require "rails_helper"

# IMP-217f4496a0a2 — BaseTool#validate_params! checked required-presence only,
# so a misspelled or unsupported parameter was dropped on the floor and the
# call answered success. For a control plane whose callers are frequently other
# models that is the worst default: nothing distinguishes "applied" from
# "ignored". The advertised per-action schema is the contract; a key outside it
# is now refused, by name, with the keys that would have been accepted.
RSpec.describe Ai::Tools::BaseTool, "unknown parameters" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe "a real registry tool (ImprovementTool#create_improvement)" do
    let(:tool) { Ai::Tools::ImprovementTool.new(account: account, user: user) }
    let(:valid) do
      {
        action: "create_improvement",
        recommendation_type: "code_lint",
        title: "Unused variable in foo",
        fingerprint: "code_lint|server/app/foo.rb|UnusedVar",
        verifier_evidence: "rubocop flags it on HEAD"
      }
    end

    it "still succeeds with only declared keys" do
      expect(tool.execute(params: valid)[:success]).to be true
    end

    it "refuses a misspelled key rather than silently dropping it" do
      expect(tool.execute(params: valid.merge(verifer_evidence: "typo"))).to include(success: false, error: /verifer_evidence/)
    end

    it "names the keys the action does accept so the caller can correct itself" do
      expect(tool.execute(params: valid.merge(bogus: 1))).to include(success: false, error: /Accepted:.*fingerprint.*verifier_evidence/m)
    end

    it "refuses a key that another action declares but this one does not" do
      # `status` is a list_improvements filter and sits on the umbrella hash;
      # create_improvement does not read it, so it would be dropped silently.
      expect(tool.execute(params: valid.merge(status: "pending"))).to include(success: false, error: /status/)
    end

    it "refuses string-keyed params the same way" do
      expect(tool.execute(params: valid.stringify_keys.merge("bogus" => 1))).to include(success: false, error: /bogus/)
    end

    it "refuses ActionController::Parameters the same way" do
      params = ActionController::Parameters.new(valid.merge(bogus: 1))
      expect(tool.execute(params: params)).to include(success: false, error: /bogus/)
    end

    it "lists every unknown key, not just the first" do
      expect(tool.execute(params: valid.merge(aaa: 1, bbb: 2))).to include(success: false, error: /aaa.*bbb/m)
    end

    it "caps what it echoes of a caller-supplied key name" do
      result = tool.execute(params: valid.merge("k" * 500 => 1))

      expect(result[:success]).to be false
      expect(result[:error].length).to be < 600
    end

    it "strips control characters from an echoed key name" do
      result = tool.execute(params: valid.merge("bad\u0007key" => 1))

      expect(result[:error]).to include("bad?key")
    end

    it "quotes echoed key names so a crafted key cannot pose as the sentence around it" do
      result = tool.execute(params: valid.merge("x. Accepted: everything" => 1))

      expect(result[:error]).to include('"x. Accepted: everything"')
    end

    it "survives a key with invalid UTF-8 bytes" do
      result = tool.execute(params: valid.merge("bad\xFFkey".b.force_encoding("UTF-8") => 1))

      expect(result[:success]).to be false
      expect(result[:error]).to include("bad?key")
    end

    it "refuses ahead of the required-presence check, so a misspelled required key reads as the typo" do
      result = tool.execute(params: valid.except(:title).merge(titel: "x"))

      expect(result[:error]).to match(/Unrecognized.*titel/)
    end

    it "does not refuse an approved replay, whose params carry keys the gate stamped" do
      allow(tool).to receive(:approved_replay?).and_return(true)

      expect(tool.send(:unknown_params_refusal, valid.merge(replay_baseline: { "a" => 1 }))).to be_nil
    end
  end

  describe "an action routed on a shortened internal name" do
    # KnowledgeGraphTool routes on "search" but declares (and advertises) it as
    # "search_knowledge_graph": the per-action entry must still be found.
    it "checks against the action's own entry, not the union over every action" do
      tool = Ai::Tools::KnowledgeGraphTool.new(account: account, user: user)

      accepted = tool.send(:accepted_param_keys, "search")
      declared = Ai::Tools::KnowledgeGraphTool.action_definitions["search_knowledge_graph"][:parameters].keys.map(&:to_s)

      expect(accepted).to match_array(declared + [ "action" ])
    end
  end

  describe "an action the tool does not declare" do
    it "is left to the undeclared-action refusal rather than answered as a parameter error" do
      tool = Ai::Tools::ImprovementTool.new(account: account, user: user)

      result = tool.execute(params: { action: "no_such_action", bogus: 1 })

      expect(result[:error]).not_to include("Unrecognized parameter")
    end
  end

  describe "keys the platform itself supplies" do
    it "always allows :action" do
      tool = Ai::Tools::ImprovementTool.new(account: account, user: user)
      expect(tool.execute(params: { action: "scoreboard" })[:success]).to be true
    end

    it "allows the pagination keys on an action that splats PAGINATION_PARAMETERS" do
      with_pagination = Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |name, klass|
        defs = klass.constantize.action_definitions[name]
        name if defs && (defs[:parameters] || {}).key?(:cursor)
      end
      expect(with_pagination).not_to be_empty

      klass = Ai::Tools::PlatformApiToolRegistry.all_tools.fetch(with_pagination.first).constantize
      tool = klass.allocate
      expect(tool.send(:unknown_param_keys, { action: with_pagination.first, cursor: "x", limit: 5 })).to be_empty
    end
  end

  describe "when the tool does not declare enough to judge" do
    # RepositoryGitTool's real shape: a JSON-Schema umbrella listing only
    # `action` and a server-bound id, whose per-verb arguments live in the
    # caller's own definitions. Rejecting here would refuse every git argument.
    let(:umbrella_only) do
      Class.new(described_class) do
        def self.name = "UmbrellaOnlyTool"

        def self.definition
          { name: "umbrella_only", description: "x",
            parameters: { type: "object", properties: { action: { type: "string" } } } }
        end
      end
    end

    it "does not refuse an undeclared key" do
      tool = umbrella_only.allocate
      expect(tool.send(:unknown_param_keys, { action: "write_file", path: "a", content: "b" })).to be_empty
    end

    it "honours an explicit additionalProperties: true" do
      open_tool = Class.new(described_class) do
        def self.name = "OpenTool"

        def self.definition
          { name: "open", description: "x", parameters: { action: { type: "string", required: true } } }
        end

        def self.action_definitions
          { "go" => { description: "x", parameters: { type: "object", additionalProperties: true,
                                                      properties: { a: { type: "string" } } } } }
        end
      end
      expect(open_tool.allocate.send(:unknown_param_keys, { action: "go", zzz: 1 })).to be_empty
    end
  end

  describe "coverage" do
    it "resolves a per-action schema for every registry action, so none is silently unchecked" do
      unresolved = Ai::Tools::PlatformApiToolRegistry.all_tools.filter_map do |action_name, class_name|
        klass = class_name.constantize
        defs = klass.action_definitions[action_name]
        action_name unless defs.is_a?(Hash) && defs[:parameters].is_a?(Hash)
      end
      expect(unresolved).to eq([]), "registry actions with no per-action parameters hash (strictness would skip them): #{unresolved.first(10).inspect}"
    end
  end
end
