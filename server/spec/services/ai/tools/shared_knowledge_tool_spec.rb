# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::SharedKnowledgeTool do
  let(:account) { create(:account) }
  # Behaviour examples, constructed as an in-process system caller. The
  # per-action gate (G4) requires that opt-in to be EXPLICIT — a nil user does
  # not imply internal. Authorization is pinned in
  # read_gated_tools_action_permission_spec.rb.
  let(:tool) { described_class.new(account: account, internal: true) }

  describe ".action_definitions" do
    it "exposes a tags filter parameter on search_knowledge" do
      params = described_class.action_definitions["search_knowledge"][:parameters]

      expect(params).to have_key(:tags)
      expect(params[:tags][:type]).to eq("array")
    end
  end

  describe "#execute action: search_knowledge" do
    # Both entries match the "widget" keyword search so, absent tag filtering,
    # both come back — the tags param is what must narrow this to one.
    # embedding left nil so the search falls back to the deterministic keyword
    # path instead of vector similarity (avoids flakiness / provider setup).
    let!(:alpha_entry) do
      create(:ai_shared_knowledge, account: account, title: "Alpha Widget Doc",
             content: "Widget assembly instructions for the alpha line.",
             tags: [ "alpha" ], embedding: nil)
    end

    let!(:beta_entry) do
      create(:ai_shared_knowledge, account: account, title: "Beta Widget Doc",
             content: "Widget assembly instructions for the beta line.",
             tags: [ "beta" ], embedding: nil)
    end

    it "filters results by the tags parameter" do
      result = tool.execute(params: { action: "search_knowledge", query: "widget", tags: [ "alpha" ] })

      expect(result[:success]).to be true
      titles = result[:entries].map { |e| e[:title] }
      expect(titles).to include("Alpha Widget Doc")
      expect(titles).not_to include("Beta Widget Doc")
    end

    it "returns all matching entries when tags is omitted" do
      result = tool.execute(params: { action: "search_knowledge", query: "widget" })

      expect(result[:success]).to be true
      titles = result[:entries].map { |e| e[:title] }
      expect(titles).to include("Alpha Widget Doc", "Beta Widget Doc")
    end
  end

  # Found in production 2026-08-02: the tags filter worked in-process but was
  # inert over MCP. The value arrives as a JSON *string* rather than an Array,
  # so `Array(params[:tags])` wrapped the literal text `["alpha"]` as ONE tag
  # and matched nothing. The same coercion feeds create/update, where it does
  # not merely miss — it PERSISTS the bogus single tag.
  describe "tags arriving as a JSON string (MCP transport)" do
    let!(:alpha) do
      Ai::Memory::SharedKnowledgeService.new(account: account).create(
        title: "Alpha Widget Doc", content: "widget alpha content",
        content_type: "text", access_level: "team", tags: %w[alpha]
      )
    end
    let!(:beta) do
      Ai::Memory::SharedKnowledgeService.new(account: account).create(
        title: "Beta Widget Doc", content: "widget beta content",
        content_type: "text", access_level: "team", tags: %w[beta]
      )
    end

    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    end

    it "parses a JSON-encoded tags string when filtering" do
      result = tool.execute(params: {
        action: "search_knowledge", query: "widget", tags: '["alpha"]'
      })

      expect(result[:success]).to be true
      expect(result[:entries].map { |e| e[:title] }).to eq(["Alpha Widget Doc"])
    end

    it "stores parsed tags on create rather than the raw JSON string" do
      result = tool.execute(params: {
        action: "create_knowledge", title: "Gamma Doc",
        content: "gamma content for tag coercion", content_type: "text",
        access_level: "team", tags: '["gamma","delta"]'
      })

      expect(result[:success]).to be true
      stored = Ai::SharedKnowledge.find(result[:entry][:id]).tags
      expect(stored).to contain_exactly("gamma", "delta")
    end

    it "still accepts a real array unchanged" do
      result = tool.execute(params: {
        action: "search_knowledge", query: "widget", tags: ["beta"]
      })

      expect(result[:entries].map { |e| e[:title] }).to eq(["Beta Widget Doc"])
    end

    it "treats a bare non-JSON string as a single tag" do
      result = tool.execute(params: {
        action: "search_knowledge", query: "widget", tags: "alpha"
      })

      expect(result[:entries].map { |e| e[:title] }).to eq(["Alpha Widget Doc"])
    end
  end

  # IMP-3c9a6dc8f0a9
  describe "#execute action: archive_by_predicate" do
    let!(:matching) { create(:ai_shared_knowledge, account: account, source_type: "import") }
    let!(:other) { create(:ai_shared_knowledge, account: account, source_type: "manual") }

    it "defaults to dry_run and mutates nothing when dry_run is omitted" do
      result = tool.execute(params: { action: "archive_by_predicate", source_type: "import" })

      expect(result[:dry_run]).to be true
      expect(matching.reload.provenance["archived"]).not_to eq(true)
    end

    it "archives only the matching rows when dry_run: false is explicit" do
      result = tool.execute(params: { action: "archive_by_predicate", source_type: "import", dry_run: false })

      expect(result[:success]).to be true
      expect(matching.reload.provenance["archived"]).to be true
      expect(other.reload.provenance["archived"]).not_to eq(true)
    end
  end

  describe "#execute action: hard_delete_archived" do
    let!(:archived) { create(:ai_shared_knowledge, account: account, provenance: { "archived" => true }) }
    let!(:not_archived) { create(:ai_shared_knowledge, account: account) }

    it "defaults to dry_run and destroys nothing when dry_run is omitted" do
      tool.execute(params: { action: "hard_delete_archived" })

      expect(Ai::SharedKnowledge.where(id: archived.id)).to exist
    end

    it "hard-deletes only already-archived rows when dry_run: false is explicit" do
      result = tool.execute(params: { action: "hard_delete_archived", dry_run: false })

      expect(result[:success]).to be true
      expect(Ai::SharedKnowledge.where(id: archived.id)).not_to exist
      expect(Ai::SharedKnowledge.where(id: not_archived.id)).to exist
    end
  end

  # IMP-a7734de23fc7 (memory-platform-exclusive|create-knowledge-key). A keyed
  # create is an UPSERT anchored on provenance->>'guidance_key', so a session
  # that edits a memory updates the row it wrote before instead of leaving a
  # near-duplicate behind for cosine dedup to mis-handle.
  describe "#execute action: create_knowledge with a key" do
    let(:key) { "memory:example-rule" }

    def create_with_key(content:, title: "Example rule", **extra)
      tool.execute(params: {
        action: "create_knowledge", key: key, title: title,
        content: content, tags: [ "memory", "memory-example-rule" ]
      }.merge(extra))
    end

    it "declares the key parameter on create_knowledge" do
      expect(described_class.action_definitions["create_knowledge"][:parameters]).to have_key(:key)
    end

    it "creates one row and reports the action" do
      result = create_with_key(content: "First body.")

      expect(result[:success]).to be true
      expect(result[:action]).to eq("created")
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(1)
    end

    it "updates that same row in place on a second call with the same key" do
      create_with_key(content: "First body.")
      result = create_with_key(content: "Second body, edited.")

      expect(result[:success]).to be true
      expect(result[:action]).to eq("updated")
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(1)
      expect(Ai::SharedKnowledge.where(account: account).first.content).to eq("Second body, edited.")
    end

    it "reports unchanged and rewrites nothing when the content is identical" do
      create_with_key(content: "Same body.")
      result = create_with_key(content: "Same body.")

      expect(result[:action]).to eq("unchanged")
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(1)
    end

    it "anchors the row on the key and keeps the caller's tags" do
      create_with_key(content: "Body.")
      entry = Ai::SharedKnowledge.where(account: account).first

      expect(entry.provenance["guidance_key"]).to eq(key)
      expect(entry.tags).to include("memory", "memory-example-rule")
      expect(entry.access_level).to eq("account")
    end

    it "refuses a malformed key instead of writing an unanchored row" do
      result = tool.execute(params: {
        action: "create_knowledge", key: "no-prefix", title: "T", content: "C"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/key/i)
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)
    end

    it "leaves the unkeyed create path alone" do
      result = tool.execute(params: {
        action: "create_knowledge", title: "Unkeyed", content: "Plain body."
      })

      expect(result[:success]).to be true
      expect(result[:action]).to be_nil
      expect(Ai::SharedKnowledge.where(account: account).first.provenance["guidance_key"]).to be_nil
    end

    it "stores the caller's content_type rather than a fixed one" do
      create_with_key(content: "Body.", content_type: "markdown")

      expect(Ai::SharedKnowledge.where(account: account).first.content_type).to eq("markdown")
    end

    it "refuses an invalid content_type" do
      result = create_with_key(content: "Body.", content_type: "not-a-type")

      expect(result[:success]).to be false
      expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)
    end

    it "ignores access_level: a keyed write is always account-scoped" do
      create_with_key(content: "Body.", access_level: "global")

      expect(Ai::SharedKnowledge.where(account: account).first.access_level).to eq("account")
    end

    it "keeps tags written earlier when a later write omits them" do
      create_with_key(content: "First body.", tags: [ "memory", "worktrees" ])
      tool.execute(params: { action: "create_knowledge", key: key, title: "Example rule",
                             content: "Second body." })

      expect(Ai::SharedKnowledge.where(account: account).first.tags).to include("worktrees")
    end

    it "rewrites nothing when the content is identical" do
      create_with_key(content: "Same body.")
      before = Ai::SharedKnowledge.where(account: account).first

      create_with_key(content: "Same body.")

      expect(before.reload.updated_at).to eq(before.updated_at)
      expect(before.integrity_hash).to eq(Digest::SHA256.hexdigest("Same body."))
    end

    it "revives an archived entry instead of reporting a hidden row as unchanged" do
      create_with_key(content: "Same body.")
      entry = Ai::SharedKnowledge.where(account: account).first
      entry.update!(provenance: entry.provenance.merge("archived" => true, "archived_at" => Time.current.iso8601))

      result = create_with_key(content: "Same body.")

      expect(result[:action]).to eq("updated")
      expect(entry.reload.provenance).not_to have_key("archived")
      expect(Ai::SharedKnowledge.where(account: account).not_archived.count).to eq(1)
    end

    it "anchors per account: the same key in another account is a separate row" do
      create_with_key(content: "Body.")
      other_account = create(:account)
      other_tool = described_class.new(account: other_account, internal: true)

      other_tool.execute(params: { action: "create_knowledge", key: key, title: "Example rule",
                                   content: "Other account body." })

      expect(Ai::SharedKnowledge.where(account: account).count).to eq(1)
      expect(Ai::SharedKnowledge.where(account: other_account).count).to eq(1)
    end

    # Gate #9, BOTH arms. The gate exists so content naming a private extension
    # never reaches the PUBLIC guidance corpus — and corpus membership is by tag,
    # which a caller chooses independently of the key.
    describe "gate #9 (private-extension refusal)" do
      let(:private_content) { "Route through Someprivate::Service for this." }

      # The seeder derives the private-extension names from the filesystem
      # (Dir.glob on a Pathname), so the fixture is injected there rather than
      # depending on whether this checkout happens to carry extensions/private.
      before do
        allow(Dir).to receive(:glob).and_wrap_original do |original, *args|
          args.first.to_s.include?("extensions/private") ? [ "/repo/extensions/private/someprivate" ] : original.call(*args)
        end
        allow(File).to receive(:directory?).and_wrap_original do |original, *args|
          args.first.to_s == "/repo/extensions/private/someprivate" || original.call(*args)
        end
      end

      it "refuses a guidance-prefixed write whose content names a private extension" do
        result = tool.execute(params: { action: "create_knowledge", key: "guidance:ext-notes",
                                        title: "Notes", content: private_content })

        expect(result[:success]).to be false
        expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)
      end

      it "refuses when a non-guidance key carries guidance tags into that corpus" do
        result = tool.execute(params: { action: "create_knowledge", key: "memory:ext-notes",
                                        title: "Notes", content: private_content,
                                        tags: [ "guidance", "guidance-ext-notes" ] })

        expect(result[:success]).to be false
        expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)
      end

      it "allows the same content under a memory key with no guidance tags" do
        result = tool.execute(params: { action: "create_knowledge", key: "memory:ext-notes",
                                        title: "Notes", content: private_content,
                                        tags: [ "memory" ] })

        expect(result[:success]).to be true
        expect(Ai::SharedKnowledge.where(account: account).count).to eq(1)
      end
    end

    it "exposes guidance_key through search_knowledge results" do
      create_with_key(content: "Searchable body about widgets.")
      # Same convention as the search examples above: drop the embedding so the
      # search takes the deterministic keyword path rather than vector
      # similarity, whose threshold would otherwise decide what this example sees.
      Ai::SharedKnowledge.where(account: account).update_all(embedding: nil)

      result = tool.execute(params: { action: "search_knowledge", query: "widgets", tags: [ "memory" ] })

      expect(result[:success]).to be true
      expect(result[:entries].first[:provenance]["guidance_key"]).to eq(key)
    end
  end
end
