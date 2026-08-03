# frozen_string_literal: true

require "rails_helper"

# Retrieval evaluation 2026-08-03 (docs/operations/code-index-retrieval-quality.md)
# established that no ranking change reaches a symbol whose vocabulary is disjoint from
# the query — the corpus itself has to be rewritten into query-shaped prose. This service
# does that rewrite, so the properties it must hold are:
#   - it spends money, so scope/limit/dry-run must be exact
#   - a summary that does not clear the vector never reaches search at all
#   - a 60k-node run must survive a bad batch and resume without redoing finished work
RSpec.describe Ai::Codebase::SymbolSummaryService do
  let(:account) { create(:account) }
  let(:knowledge_base) { create(:ai_knowledge_base, account: account) }
  let(:base_path) { Dir.mktmpdir }
  let(:service) do
    described_class.new(account: account, knowledge_base: knowledge_base, base_path: base_path)
  end

  after { FileUtils.remove_entry(base_path) if File.directory?(base_path) }

  def symbol_node(name:, entity_type: "method", properties: {}, embedding: nil)
    create(:ai_knowledge_graph_node,
           account: account, knowledge_base: knowledge_base,
           name: name, node_type: "code_entity", entity_type: entity_type,
           description: "method `#{name}`", properties: properties,
           embedding: embedding, status: "active")
  end

  # Stubs the provider layer LlmTriagePipeline resolves through, and returns the double
  # so a test can assert on the prompt it received.
  def stub_llm(content:, model: "test-model-1")
    provider = double("provider", available_models: [ { "id" => model } ])
    client   = double("client", provider: provider)
    allow(Ai::Llm::Client).to receive(:for_account).and_return(client)
    allow(client).to receive(:complete).and_return(double("resp", content: content))
    client
  end

  def results_json(*summaries)
    { "results" => summaries.each_with_index.map { |s, i| { "index" => i, "summary" => s } } }.to_json
  end

  describe "#summarize! scope" do
    it "summarises only behavioural symbols — never constants, files, or containers" do
      m = symbol_node(name: "Svc#halt!", entity_type: "method")
      c = symbol_node(name: "Svc::LIMIT", entity_type: "constant")
      f = symbol_node(name: "app/svc.rb", entity_type: "file")
      # Containers are the expensive mistake: a class/module summary describes
      # everything it contains, so it matches every query aimed at any member while
      # carrying almost no damped length. Measured on the 2026-08-03 pilot, that sent
      # the correct method from rank 2 to off the list on its own identifier query.
      k = symbol_node(name: "Svc", entity_type: "class")
      mod = symbol_node(name: "Autonomy", entity_type: "module")
      # Enough results for ALL five nodes: if the scope wrongly included any of them
      # they would each get one. A single-result stub would leave them blank for the
      # wrong reason and the test would still pass with the exclusion deleted.
      client = stub_llm(content: results_json("stops everything right away", "b", "c", "d", "e"))

      service.summarize!

      # Only the method was ever sent to the model.
      prompt = nil
      expect(client).to have_received(:complete) { |args| prompt = args[:messages].first[:content] }
      expect(prompt).to include("Svc#halt!")
      expect(prompt).not_to include("Svc::LIMIT")
      expect(prompt).not_to include("app/svc.rb")
      expect(k.reload.properties["llm_summary"]).to be_nil
      expect(mod.reload.properties["llm_summary"]).to be_nil

      expect(m.reload.properties["llm_summary"]).to eq("stops everything right away")
      # A constant's value IS its meaning, and constants are 22% of the index — paying
      # to summarise them is the single easiest way to burn budget for no retrieval gain.
      expect(c.reload.properties["llm_summary"]).to be_nil
      expect(f.reload.properties["llm_summary"]).to be_nil
    end

    it "skips nodes that already carry a summary so a re-run resumes instead of re-paying" do
      done = symbol_node(name: "A#x", properties: { "llm_summary" => "already described" })
      todo = symbol_node(name: "B#y")
      client = stub_llm(content: results_json("newly described"))

      stats = service.summarize!

      expect(stats[:candidates]).to eq(1)
      expect(todo.reload.properties["llm_summary"]).to eq("newly described")
      expect(done.reload.properties["llm_summary"]).to eq("already described")
      expect(client).to have_received(:complete).once
    end

    it "treats a blank summary as pending, not as done" do
      blank = symbol_node(name: "C#z", properties: { "llm_summary" => "" })
      stub_llm(content: results_json("a real description"))

      service.summarize!

      expect(blank.reload.properties["llm_summary"]).to eq("a real description")
    end
  end

  describe "#summarize! writes" do
    it "stores the summary and CLEARS the vector so the embed phase picks it up" do
      node = symbol_node(name: "Svc#run", embedding: Array.new(1536, 0.5))
      stub_llm(content: results_json("kicks off the nightly reconcile"))

      service.summarize!

      node.reload
      expect(node.properties["llm_summary"]).to eq("kicks off the nightly reconcile")
      expect(node.properties["llm_summary_model"]).to eq("test-model-1")
      expect(node.properties["llm_summary_at"]).to be_present
      # The embed phase only ever selects `embedding: nil`. A summary written without
      # clearing this would sit in properties forever and never reach search.
      expect(node.embedding).to be_nil
    end

    it "preserves existing properties rather than replacing the hash" do
      node = symbol_node(name: "Svc#run", properties: { "kind" => "method", "doc" => "keep me" })
      stub_llm(content: results_json("does the thing"))

      service.summarize!

      expect(node.reload.properties).to include("kind" => "method", "doc" => "keep me")
    end

    it "truncates an overlong summary to SUMMARY_MAX_CHARS" do
      node = symbol_node(name: "Svc#run")
      stub_llm(content: results_json("x" * 900))

      service.summarize!

      expect(node.reload.properties["llm_summary"].length).to eq(described_class::SUMMARY_MAX_CHARS)
    end
  end

  describe "cost controls" do
    it "dry_run counts and prices the work without calling the LLM or writing" do
      3.times { |i| symbol_node(name: "S#m#{i}") }
      client = stub_llm(content: results_json("unused"))

      stats = service.summarize!(dry_run: true)

      expect(stats[:candidates]).to eq(3)
      expect(stats[:estimated_calls]).to eq(1)
      expect(client).not_to have_received(:complete)
      expect(knowledge_base.knowledge_graph_nodes.where("properties ? 'llm_summary'").count).to eq(0)
    end

    it "limit caps how many symbols a run touches" do
      5.times { |i| symbol_node(name: "S#m#{i}") }
      stub_llm(content: results_json(*Array.new(5, "described")))

      stats = service.summarize!(limit: 2)

      expect(stats[:candidates]).to eq(2)
      expect(stats[:summarized]).to eq(2)
      expect(knowledge_base.knowledge_graph_nodes.where("properties ? 'llm_summary'").count).to eq(2)
    end

    it "batches at SUMMARY_BATCH instead of one call per symbol" do
      45.times { |i| symbol_node(name: "S#m#{i}") }
      client = stub_llm(content: results_json(*Array.new(described_class::SUMMARY_BATCH, "described")))

      service.summarize!

      # 45 nodes => 3 calls at SUMMARY_BATCH=20, not 45.
      expect(client).to have_received(:complete).exactly(3).times
    end

    it "skips entirely when the account has no LLM credential" do
      symbol_node(name: "S#m")
      allow(Ai::Llm::Client).to receive(:for_account).and_return(nil)

      stats = service.summarize!

      expect(stats[:status]).to match(/no LLM credential/)
      expect(stats[:summarized]).to eq(0)
    end
  end

  describe "resilience" do
    it "counts a failed batch and keeps going instead of aborting the run" do
      2.times { |i| symbol_node(name: "S#m#{i}") }
      provider = double("provider", available_models: [ { "id" => "test-model-1" } ])
      client = double("client", provider: provider)
      allow(Ai::Llm::Client).to receive(:for_account).and_return(client)
      allow(client).to receive(:complete).and_raise(StandardError, "provider exploded")

      stats = service.summarize!

      # Counted, not merely warned — the 2026-08-02 embed phase reported success at 8%
      # because failures never made it into stats.
      expect(stats[:failures]).to eq(2)
      expect(stats[:summarized]).to eq(0)
    end

    it "counts symbols the model omitted from its response" do
      2.times { |i| symbol_node(name: "S#m#{i}") }
      stub_llm(content: { "results" => [ { "index" => 0, "summary" => "only the first" } ] }.to_json)

      stats = service.summarize!

      expect(stats[:summarized]).to eq(1)
      expect(stats[:failures]).to eq(1)
    end

    it "tolerates markdown fences around the JSON" do
      node = symbol_node(name: "S#m")
      stub_llm(content: "```json\n#{results_json('fenced but valid')}\n```")

      service.summarize!

      expect(node.reload.properties["llm_summary"]).to eq("fenced but valid")
    end
  end

  # The flat-rate route (flatrate-cli-vs-metered-platform-loops): CLI subagents produce
  # the summaries off-platform, so no metered provider spend, and import applies them.
  describe "#import!" do
    it "applies summaries by qualified name without calling any LLM" do
      node = symbol_node(name: "Svc#run", embedding: Array.new(1536, 0.5))
      allow(Ai::Llm::Client).to receive(:for_account).and_raise("must not be called")

      stats = service.import!(
        [ { "name" => "Svc#run", "summary" => "kicks off the nightly reconcile" } ],
        source: "cli-subagent"
      )

      node.reload
      expect(stats[:summarized]).to eq(1)
      expect(node.properties["llm_summary"]).to eq("kicks off the nightly reconcile")
      expect(node.properties["llm_summary_model"]).to eq("cli-subagent")
      expect(node.embedding).to be_nil
    end

    it "counts names that are not in the index instead of dropping them silently" do
      symbol_node(name: "Svc#run")

      stats = service.import!(
        [ { "name" => "Svc#run", "summary" => "ok" },
          { "name" => "Gone#missing", "summary" => "orphan" } ],
        source: "cli-subagent"
      )

      # A stale name means the producer used a different checkout than the index.
      # Silently dropping these would report a clean run over a partial import.
      expect(stats[:summarized]).to eq(1)
      expect(stats[:missing]).to eq(1)
    end

    it "counts malformed records" do
      stats = service.import!(
        [ { "name" => "", "summary" => "no name" }, { "name" => "X#y", "summary" => "  " } ],
        source: "cli-subagent"
      )

      expect(stats[:failures]).to eq(2)
      expect(stats[:summarized]).to eq(0)
    end

    it "dry_run writes nothing" do
      node = symbol_node(name: "Svc#run")

      stats = service.import!(
        [ { "name" => "Svc#run", "summary" => "would be applied" } ],
        source: "cli-subagent", dry_run: true
      )

      expect(stats[:candidates]).to eq(1)
      expect(node.reload.properties["llm_summary"]).to be_nil
    end
  end

  describe "body snippets" do
    it "sends the symbol's actual body lines to the model" do
      File.write(File.join(base_path, "svc.rb"), (1..10).map { |n| "line#{n}\n" }.join)
      symbol_node(name: "Svc#run", properties: {
        "file_path" => "svc.rb", "line_start" => 3, "line_end" => 5
      })
      client = stub_llm(content: results_json("described"))

      service.summarize!

      prompt = nil
      expect(client).to have_received(:complete) { |args| prompt = args[:messages].first[:content] }
      # The body is the ONLY behavioural text for the ~61% of symbols with no doc
      # comment — precisely the ones retrieval loses today.
      expect(prompt).to include("line3", "line4", "line5")
      expect(prompt).not_to include("line6")
    end

    it "falls back to signature-only when the file is missing" do
      symbol_node(name: "Svc#run", properties: {
        "file_path" => "gone.rb", "line_start" => 1, "line_end" => 3
      })
      stub_llm(content: results_json("described anyway"))

      stats = service.summarize!

      expect(stats[:summarized]).to eq(1)
      expect(stats[:skipped_no_body]).to eq(1)
    end

    it "refuses to read a file_path that escapes base_path" do
      secret = File.join(Dir.tmpdir, "outside-#{SecureRandom.hex(4)}.rb")
      File.write(secret, "TOP_SECRET_CONTENT\n")
      symbol_node(name: "Svc#run", properties: {
        "file_path" => "../#{File.basename(secret)}", "line_start" => 1, "line_end" => 1
      })
      client = stub_llm(content: results_json("described"))

      service.summarize!

      prompt = nil
      expect(client).to have_received(:complete) { |args| prompt = args[:messages].first[:content] }
      expect(prompt).not_to include("TOP_SECRET_CONTENT")
    ensure
      FileUtils.rm_f(secret)
    end

    it "caps the snippet at BODY_MAX_LINES for a huge symbol" do
      File.write(File.join(base_path, "big.rb"), (1..500).map { |n| "row#{n}\n" }.join)
      symbol_node(name: "Svc#big", properties: {
        "file_path" => "big.rb", "line_start" => 1, "line_end" => 400
      })
      client = stub_llm(content: results_json("described"))

      service.summarize!

      prompt = nil
      expect(client).to have_received(:complete) { |args| prompt = args[:messages].first[:content] }
      expect(prompt).to include("row#{described_class::BODY_MAX_LINES}")
      expect(prompt).not_to include("row#{described_class::BODY_MAX_LINES + 1}")
    end
  end
end
