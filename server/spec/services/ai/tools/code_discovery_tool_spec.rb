# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::CodeDiscoveryTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("code_discovery")
      expect(defn[:parameters]).to include(:action, :repository_id, :query)
    end
  end

  # Live symptom on the fleet control plane 2026-08-02: with the repository
  # correctly registered, semantic_search still failed with "Repository
  # 'powernode-platform' has no local_path in metadata". It queries
  # knowledge-graph rows and never touches the filesystem — it discards the
  # base_path it was forcing to resolve — so requiring a working copy to exist
  # on the server made pure vector search impossible on any node not hosting a
  # checkout.
  describe "#execute action=semantic_search without a repository local_path" do
    let!(:repository) do
      create(:git_repository, account: account, full_name: "nodealchemy/powernode-platform", metadata: {})
    end

    it "does not demand a filesystem path it never uses" do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(Array.new(1536) { 0.01 })

      result = tool.execute(params: {
        action: "semantic_search", query: "hostname envelope",
        repository_id: "nodealchemy/powernode-platform"
      })

      expect(result[:error].to_s).not_to include("local_path")
      expect(result[:success]).to be true
    end
  end

  describe "#execute action=semantic_search" do
    it "requires a query" do
      result = tool.execute(params: { action: "semantic_search", repository_id: "whatever" })
      expect(result).to eq({ success: false, error: "query is required" })
    end

    it "requires a repository_id" do
      result = tool.execute(params: { action: "semantic_search", query: "find the thing" })
      expect(result).to eq({ success: false, error: "repository_id is required" })
    end

    context "when repository_id does not match any repository for the account" do
      it "surfaces a self-correcting error listing the account's available repositories" do
        create(:git_repository, account: account, full_name: "nodealchemy/powernode-platform")
        create(:git_repository, account: account, full_name: "nodealchemy/other-repo")

        result = tool.execute(params: {
          action: "semantic_search",
          repository_id: "powernode",
          query: "embedding service"
        })

        expect(result[:success]).to be false
        expect(result[:error]).to include("repository not found: powernode")
        expect(result[:error]).to include("nodealchemy/powernode-platform")
        expect(result[:error]).to include("nodealchemy/other-repo")
      end

      it "never leaks another account's repositories" do
        other_account = create(:account)
        create(:git_repository, account: other_account, full_name: "other/secret-repo")

        result = tool.execute(params: {
          action: "semantic_search",
          repository_id: "powernode",
          query: "embedding service"
        })

        expect(result[:success]).to be false
        expect(result[:error]).not_to include("secret-repo")
        expect(result[:error]).to include("no git repositories")
      end
    end
  end

  # Measured 2026-08-03 (docs/operations/code-index-retrieval-quality.md):
  # pure vector search answered identifier-shaped queries well (0.73) but could
  # not retrieve KillSwitchService#emergency_halt! for "immediately stop a
  # runaway autonomous agent" — not even in the top TEN — despite that node
  # carrying the doc "Coordinated emergency stop — halts ALL agentic activity".
  # Three attempts at enriching the corpus did not fix it. The lexical arm
  # recovers it because the answer IS reachable by a word in the query.
  describe "hybrid retrieval" do
    let!(:repository) do
      create(:git_repository, account: account, full_name: "acme/app", metadata: {})
    end
    let!(:kb) { create(:ai_knowledge_base, account: account, git_repository_id: repository.id) }

    def node(simple, description, embedding: nil, mentions: 1)
      create(:ai_knowledge_graph_node,
             account: account, knowledge_base: kb,
             name: "app/svc.rb::Svc##{simple}", node_type: "code_entity", entity_type: "method",
             description: description, embedding: embedding, status: "active",
             mention_count: mentions,
             properties: { "simple_name" => simple, "file_path" => "app/svc.rb" })
    end

    def search(query, top_k: 5)
      tool.execute(params: { action: "semantic_search", query: query,
                             repository_id: "acme/app", top_k: top_k })
    end

    # Only the decoys are embedded, so the vector arm can never return the
    # target — exactly the situation measured in production.
    def setup_target_invisible_to_vector!
      target = node("emergency_halt!", "Coordinated emergency stop - halts ALL agentic activity for an account.")
      decoys = 3.times.map { |i| node("unrelated_#{i}", "something else entirely", embedding: Array.new(1536) { 0.01 }) }
      [target, decoys]
    end

    before do
      # Document-frequency weights are cached per scope; without this, one
      # example's corpus statistics leak into the next.
      Rails.cache.clear
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(Array.new(1536) { 0.01 })
    end

    it "surfaces a behavioural match the vector arm cannot return at all" do
      target, = setup_target_invisible_to_vector!

      result = search("immediately stop a runaway autonomous agent")

      expect(result[:success]).to be true
      ids = result[:results].map { |r| r[:id] }
      expect(ids).to include(target.id), "lexical arm must recover what the vector arm cannot see"
      expect(result[:retrieval][:mode]).to eq("hybrid")
    end

    # The exact production failure, now with a summary attached: `emergency_halt!`
    # describes itself as "Coordinated emergency stop" and never matched "runaway
    # autonomous agent" in any of three rounds. The LLM summary is the only text
    # carrying the searcher's vocabulary — if the lexical arm cannot see it, the
    # summary is reachable by the vector arm alone and we have paid for half a fix.
    it "reaches a symbol through its LLM summary when the name and description share no query words" do
      target = create(:ai_knowledge_graph_node,
                      account: account, knowledge_base: kb,
                      name: "app/svc.rb::Svc#emergency_halt!", node_type: "code_entity",
                      entity_type: "method", status: "active", mention_count: 1,
                      description: "method `emergency_halt!` - params: (reason:, triggered_by:)",
                      properties: {
                        "simple_name" => "emergency_halt!", "file_path" => "app/svc.rb",
                        "llm_summary" => "immediately stops a runaway autonomous agent from taking further action"
                      })
      3.times { |i| node("unrelated_#{i}", "something else entirely", embedding: Array.new(1536) { 0.01 }) }

      hit = search("runaway autonomous agent").fetch(:results).find { |r| r[:id] == target.id }

      expect(hit).to be_present, "the summary must be lexically searchable, not vector-only"
      expect(hit[:matched_by]).to include("lexical")
    end

    # Measured 2026-08-03: for "kill switch emergency halt" the top three candidates
    # all matched all four terms (raw 16.15, tied at the maximum), so ordering fell
    # entirely to the damping divisor and `emergency_halt!` placed last of the three
    # purely because its description was the longest — which it was because it is the
    # best documented. Coverage must outrank brevity.
    it "prefers a complete term match over a terser partial one" do
      complete = create(:ai_knowledge_graph_node,
                        account: account, knowledge_base: kb, node_type: "code_entity",
                        entity_type: "method", status: "active", mention_count: 1,
                        name: "app/svc.rb::Svc#emergency_halt!",
                        description: "method `emergency_halt!` - in server/app/services/ai/autonomy/" \
                                     "kill_switch_service.rb - params: (reason:, triggered_by:) - " \
                                     "Coordinated emergency stop that halts every agentic workflow for " \
                                     "an account, opens all circuit breakers, cancels queued executions " \
                                     "and records an audit event describing who triggered the halt and why.",
                        properties: { "simple_name" => "emergency_halt!", "file_path" => "app/svc.rb" })
      terse = create(:ai_knowledge_graph_node,
                     account: account, knowledge_base: kb, node_type: "code_entity",
                     entity_type: "method", status: "active", mention_count: 1,
                     name: "app/other.rb::Other#halt_switch",
                     description: "halt switch",
                     properties: { "simple_name" => "halt_switch", "file_path" => "app/other.rb" })
      6.times { |i| node("filler_#{i}", "unrelated helper number #{i}") }

      ids = search("emergency halt switch").fetch(:results).map { |r| r[:id] }

      # `complete` matches all three terms; `terse` matches two and is ~20x shorter,
      # so damping alone would hand it the top slot.
      expect(ids.index(complete.id)).to be < ids.index(terse.id),
        "a candidate matching every query term must outrank a shorter partial match"
    end

    # Measured 2026-08-03: at equal coverage, a flat bag-of-fields scored
    # `emergency_halt!` (terms in its own identifier) the same as `kill_switch_active?`
    # (the same terms only in generated summary prose), then ordered them by brevity.
    # Where a term matches is evidence about how strong the match is.
    it "weights an author's doc match above a generated-summary match, all else equal" do
      # Isolating the field is the whole point, so everything else is held equal.
      # Both strings are the same length and both simple_names are the same length, so
      # the damp sources match exactly and damping cancels out. mention_count favours
      # the summary node, which is the final tiebreak — so if the field weights were
      # flat, the scores would tie and the SUMMARY node would win. Note the fixture
      # cannot reuse build_description's real output: that embeds the identifier, so a
      # name match is always also a description match and the fields stop being
      # independent variables.
      terms_text = "triggers an emergency halt across the account"
      plain_text = "performs a routine cleanup across the account"
      expect(terms_text.length).to eq(plain_text.length) # guard the premise

      doc_node = create(:ai_knowledge_graph_node,
                        account: account, knowledge_base: kb, node_type: "code_entity",
                        entity_type: "method", status: "active", mention_count: 1,
                        name: "app/a.rb::A#alpha_handler", description: terms_text,
                        properties: { "simple_name" => "alpha_handler", "file_path" => "app/a.rb" })
      summary_node = create(:ai_knowledge_graph_node,
                            account: account, knowledge_base: kb, node_type: "code_entity",
                            entity_type: "method", status: "active", mention_count: 9,
                            name: "app/b.rb::B#beta_handlerx", description: plain_text,
                            properties: { "simple_name" => "beta_handlerx", "file_path" => "app/b.rb",
                                          "llm_summary" => terms_text })
      6.times { |i| node("filler_#{i}", "unrelated helper number #{i}") }

      ids = search("emergency halt").fetch(:results).map { |r| r[:id] }

      expect(ids).to include(doc_node.id, summary_node.id)
      expect(ids.index(doc_node.id)).to be < ids.index(summary_node.id),
        "the author's own words are stronger evidence than generated prose"
    end

    it "labels which arm found each result" do
      target, = setup_target_invisible_to_vector!

      hit = search("emergency stop agentic").fetch(:results).find { |r| r[:id] == target.id }

      expect(hit[:matched_by]).to eq(["lexical"])
      expect(hit[:lexical_rank]).to be_present
      expect(hit[:vector_rank]).to be_nil
    end

    it "ranks a node matching more query terms above one matching fewer" do
      # Filler so neither term matches the ENTIRE corpus -- a term present in
      # every document carries no signal and is correctly weighted out.
      3.times { |i| node("filler_#{i}", "unrelated text") }
      both = node("halt_agent", "stops the agent")
      one  = node("halt_only", "stops a job")

      ids = search("halt agent").fetch(:results).map { |r| r[:id] }

      expect(ids.index(both.id)).to be < ids.index(one.id)
    end

    # First live run of the fusion put PlatformResilienceExecutor above
    # KillSwitchService#emergency_halt! for "immediately stop a runaway
    # autonomous agent", purely because its long doc contained the ubiquitous
    # words "action"/"autonomous"/"agent". Matching a rare word is evidence;
    # matching "agent" in an agent platform is not.
    it "weights a rare term above a ubiquitous one" do
      10.times { |i| node("handler_#{i}", "processes an agent request for the agent queue") }
      rare = node("interrupt_loop", "stops a runaway process")

      ids = search("runaway agent").fetch(:results).map { |r| r[:id] }

      expect(ids.first).to eq(rare.id)
    end

    # Same failure seen live: a verbose doc should not win on volume alone.
    it "damps a long doc that matches the same term as a short precise one" do
      # Both contain BOTH query terms, so raw term-count ties them and only
      # length damping can separate them.
      verbose = node("general_executor",
                     "Action-discriminated executor covering emergency handling: the operator or an " \
                     "autonomous agent picks a sub-action and the executor routes it, and it can stop " \
                     "a branch, resume a branch, compose with maintenance and deploy flows, and wrap " \
                     "any existing primitive with a great deal of further long-winded prose besides.",
                     mentions: 50)
      precise = node("emergency_halt!", "Coordinated emergency stop.", mentions: 1)
      5.times { |i| node("noise_#{i}", "unrelated filler text") }

      ids = search("emergency stop").fetch(:results).map { |r| r[:id] }

      expect(ids.index(precise.id)).to be < (ids.index(verbose.id) || 999)
    end

    it "degrades to lexical-only instead of failing when embeddings are down" do
      target, = setup_target_invisible_to_vector!
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_raise(Ai::Memory::EmbeddingService::EmbeddingError, "worker down")

      result = search("emergency stop agentic")

      expect(result[:success]).to be true
      expect(result[:retrieval][:mode]).to eq("lexical_only")
      expect(result[:results].map { |r| r[:id] }).to include(target.id)
    end

    it "drops stopwords and short tokens so they cannot match the whole corpus" do
      expect(tool.send(:query_terms, "how do I stop an agent from the queue"))
        .to eq(%w[stop agent queue])
    end

    it "still answers identifier-shaped queries, which vector search already did well" do
      target = node("emergency_halt!", "Coordinated emergency stop.",
                    embedding: Array.new(1536) { 0.01 })

      expect(search("emergency_halt").fetch(:results).map { |r| r[:id] }).to include(target.id)
    end
  end
end
