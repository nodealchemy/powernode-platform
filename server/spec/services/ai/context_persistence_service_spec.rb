# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ContextPersistenceService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # ===========================================================================
  # .create_context
  # ===========================================================================

  describe ".create_context" do
    it "creates a new persistent context" do
      context = described_class.create_context(
        account: account,
        attributes: {
          name: "Test Context",
          context_type: "knowledge_base",
          scope: "account",
          description: "A test context"
        },
        created_by: user
      )

      expect(context).to be_persisted
      expect(context.name).to eq("Test Context")
      expect(context.context_type).to eq("knowledge_base")
      expect(context.scope).to eq("account")
      expect(context.account).to eq(account)
    end

    it "defaults context_type to knowledge_base" do
      context = described_class.create_context(
        account: account,
        attributes: { name: "Defaults Test" }
      )

      expect(context.context_type).to eq("knowledge_base")
    end

    it "defaults scope to account" do
      context = described_class.create_context(
        account: account,
        attributes: { name: "Scope Test" }
      )

      expect(context.scope).to eq("account")
    end

    it "raises ValidationError for invalid attributes" do
      expect {
        described_class.create_context(
          account: account,
          attributes: { name: nil }
        )
      }.to raise_error(Ai::ContextPersistenceService::ValidationError)
    end
  end

  # ===========================================================================
  # .find_context
  # ===========================================================================

  describe ".find_context" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             name: "Find Me",
             context_type: "knowledge_base",
             scope: "account")
    end

    it "finds context by ID" do
      found = described_class.find_context(
        account: account,
        context_id: context.id
      )

      expect(found).to eq(context)
    end

    it "raises NotFoundError for nonexistent context" do
      expect {
        described_class.find_context(
          account: account,
          context_id: SecureRandom.uuid
        )
      }.to raise_error(Ai::ContextPersistenceService::NotFoundError)
    end

    it "does not find contexts from another account" do
      other_account = create(:account)

      expect {
        described_class.find_context(
          account: other_account,
          context_id: context.id
        )
      }.to raise_error(Ai::ContextPersistenceService::NotFoundError)
    end
  end

  # ===========================================================================
  # .update_context
  # ===========================================================================

  describe ".update_context" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             name: "Original Name",
             context_type: "knowledge_base",
             scope: "account")
    end

    it "updates context attributes" do
      updated = described_class.update_context(
        account: account,
        context_id: context.id,
        attributes: { name: "Updated Name", description: "New description" }
      )

      expect(updated.name).to eq("Updated Name")
      expect(updated.description).to eq("New description")
    end

    it "raises NotFoundError for missing context" do
      expect {
        described_class.update_context(
          account: account,
          context_id: SecureRandom.uuid,
          attributes: { name: "Test" }
        )
      }.to raise_error(Ai::ContextPersistenceService::NotFoundError)
    end
  end

  # ===========================================================================
  # .archive_context
  # ===========================================================================

  describe ".archive_context" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             name: "Archive Me",
             context_type: "knowledge_base",
             scope: "account")
    end

    it "archives the context" do
      result = described_class.archive_context(
        account: account,
        context_id: context.id
      )

      result.reload
      expect(result.archived_at).to be_present
    end
  end

  # ===========================================================================
  # .clone_context
  # ===========================================================================

  describe ".clone_context" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             name: "Original",
             context_type: "knowledge_base",
             scope: "account")
    end

    let!(:entry) do
      create(:ai_context_entry,
             persistent_context: context,
             entry_key: "test_key",
             content: { "data" => "test value" })
    end

    it "creates a new context with cloned data" do
      cloned = described_class.clone_context(
        account: account,
        context_id: context.id,
        new_name: "Cloned Context"
      )

      expect(cloned).to be_persisted
      expect(cloned.name).to eq("Cloned Context")
      expect(cloned.context_type).to eq(context.context_type)
      expect(cloned.id).not_to eq(context.id)
    end

    it "clones entries from original context" do
      cloned = described_class.clone_context(
        account: account,
        context_id: context.id,
        new_name: "Cloned With Entries"
      )

      expect(cloned.context_entries.count).to eq(1)
      cloned_entry = cloned.context_entries.first
      expect(cloned_entry.entry_key).to eq("test_key")
    end
  end

  # ===========================================================================
  # Entry management
  # ===========================================================================

  describe ".add_entry" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             name: "Entry Context",
             context_type: "knowledge_base",
             scope: "account")
    end

    it "adds an entry to the context" do
      entry = described_class.add_entry(
        context: context,
        attributes: {
          key: "my_key",
          type: "fact",
          content: { "data" => "some data" },
          importance_score: 0.8
        }
      )

      expect(entry).to be_persisted
      expect(entry.entry_key).to eq("my_key")
      expect(entry.entry_type).to eq("fact")
      expect(entry.importance_score).to eq(0.8)
    end

    it "raises ValidationError for missing content" do
      expect {
        described_class.add_entry(
          context: context,
          attributes: { key: "bad_entry", content: nil }
        )
      }.to raise_error(Ai::ContextPersistenceService::ValidationError)
    end
  end

  describe ".get_entry" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             context_type: "knowledge_base",
             scope: "account")
    end

    let!(:entry) do
      create(:ai_context_entry,
             persistent_context: context,
             entry_key: "lookup_key",
             content: { "data" => "stored value" })
    end

    it "retrieves entry by key" do
      found = described_class.get_entry(context: context, key: "lookup_key")

      expect(found.entry_key).to eq("lookup_key")
    end

    it "raises NotFoundError for missing entry" do
      expect {
        described_class.get_entry(context: context, key: "nonexistent")
      }.to raise_error(Ai::ContextPersistenceService::NotFoundError)
    end
  end

  describe ".delete_entry" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             context_type: "knowledge_base",
             scope: "account")
    end

    let!(:entry) do
      create(:ai_context_entry,
             persistent_context: context,
             entry_key: "delete_me")
    end

    it "deletes the entry" do
      result = described_class.delete_entry(context: context, key: "delete_me")

      expect(result).to be true
      expect(context.context_entries.find_by(entry_key: "delete_me")).to be_nil
    end

    it "raises NotFoundError for nonexistent entry" do
      expect {
        described_class.delete_entry(context: context, key: "nonexistent")
      }.to raise_error(Ai::ContextPersistenceService::NotFoundError)
    end
  end

  # ===========================================================================
  # Search
  # ===========================================================================

  describe ".search" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             context_type: "knowledge_base",
             scope: "account")
    end

    let!(:entry1) do
      create(:ai_context_entry,
             persistent_context: context,
             entry_key: "ruby_basics",
             content: { "text" => "Ruby is a programming language" },
             content_text: "Ruby is a programming language",
             importance_score: 0.9)
    end

    let!(:entry2) do
      create(:ai_context_entry,
             persistent_context: context,
             entry_key: "python_basics",
             content: { "text" => "Python is another programming language" },
             content_text: "Python is another programming language",
             importance_score: 0.7)
    end

    it "finds entries by text query" do
      results = described_class.search(context: context, query: "Ruby")

      expect(results.map(&:entry_key)).to include("ruby_basics")
    end

    it "returns empty results for non-matching query" do
      results = described_class.search(context: context, query: "zzz_nonexistent_xyz")

      expect(results).to be_empty
    end

    it "respects limit parameter" do
      results = described_class.search(context: context, query: "programming", limit: 1)

      expect(results.size).to eq(1)
    end

    it "sanitizes SQL special characters in query" do
      expect {
        described_class.search(context: context, query: "test%_'")
      }.not_to raise_error
    end
  end

  # ===========================================================================
  # Agent Memory
  # ===========================================================================

  describe ".get_agent_memory" do
    it "creates agent memory context when missing" do
      context = described_class.get_agent_memory(account: account, agent: agent)

      expect(context).to be_persisted
      expect(context.context_type).to eq("agent_memory")
      expect(context.ai_agent_id).to eq(agent.id)
      expect(context.name).to include(agent.name)
    end

    it "returns existing agent memory context" do
      first = described_class.get_agent_memory(account: account, agent: agent)
      second = described_class.get_agent_memory(account: account, agent: agent)

      expect(first.id).to eq(second.id)
    end

    it "returns nil when create_if_missing is false and no context exists" do
      result = described_class.get_agent_memory(
        account: account,
        agent: agent,
        create_if_missing: false
      )

      expect(result).to be_nil
    end
  end

  describe ".store_memory" do
    it "stores a new memory entry" do
      described_class.store_memory(
        agent: agent,
        key: "user_preference",
        value: { "language" => "ruby" }
      )

      context = described_class.get_agent_memory(account: account, agent: agent)
      entry = context.context_entries.find_by(entry_key: "user_preference")
      expect(entry).to be_present
      expect(entry.content).to include("language" => "ruby")
    end

    it "updates existing memory entry" do
      described_class.store_memory(
        agent: agent,
        key: "user_preference",
        value: { "language" => "ruby" }
      )

      described_class.store_memory(
        agent: agent,
        key: "user_preference",
        value: { "language" => "python" }
      )

      context = described_class.get_agent_memory(account: account, agent: agent)
      entries = context.context_entries.where(entry_key: "user_preference").where(archived_at: nil)
      # Should have one active entry with the updated value
      expect(entries.count).to eq(1)
    end
  end

  describe ".recall_memory" do
    it "recalls stored memory" do
      described_class.store_memory(
        agent: agent,
        key: "fact_1",
        value: { "data" => "important fact" }
      )

      result = described_class.recall_memory(agent: agent, key: "fact_1")

      expect(result).to include("data" => "important fact")
    end

    it "returns nil for nonexistent memory" do
      result = described_class.recall_memory(agent: agent, key: "nonexistent")

      expect(result).to be_nil
    end
  end

  describe ".get_relevant_memories" do
    before do
      described_class.store_memory(agent: agent, key: "mem_1", value: { "text" => "Ruby programming tips" })
      described_class.store_memory(agent: agent, key: "mem_2", value: { "text" => "Database optimization" })
    end

    it "returns recent memories when no query provided" do
      results = described_class.get_relevant_memories(agent: agent, limit: 10)

      expect(results).to be_present
    end

    it "returns empty array when agent has no memory context" do
      other_agent = create(:ai_agent, account: account, provider: provider)

      results = described_class.get_relevant_memories(agent: other_agent)

      expect(results).to eq([])
    end
  end

  # ===========================================================================
  # Export/Import
  # ===========================================================================

  describe ".export_context" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             context_type: "knowledge_base",
             scope: "account")
    end

    let!(:entry) do
      create(:ai_context_entry,
             persistent_context: context,
             entry_key: "export_key",
             content: { "data" => "export value" })
    end

    it "exports context as JSON string" do
      result = described_class.export_context(context: context, format: :json)

      parsed = JSON.parse(result)
      expect(parsed).to have_key("context")
      expect(parsed).to have_key("entries")
      expect(parsed).to have_key("exported_at")
      expect(parsed["entries"].size).to eq(1)
    end

    it "exports context as hash" do
      result = described_class.export_context(context: context, format: :hash)

      expect(result).to be_a(Hash)
      expect(result[:context]).to be_present
      expect(result[:entries]).to be_an(Array)
    end
  end

  describe ".import_context" do
    it "imports context from data hash" do
      data = {
        context: {
          name: "Imported Context",
          context_type: "knowledge_base",
          scope: "account"
        },
        entries: [
          {
            key: "imported_key",
            type: "fact",
            content: { "data" => "imported value" },
            source_type: "import"
          }
        ]
      }

      context = described_class.import_context(account: account, data: data)

      expect(context).to be_persisted
      expect(context.name).to eq("Imported Context")
      expect(context.context_entries.count).to eq(1)
    end
  end

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    let!(:context) do
      create(:ai_persistent_context,
             account: account,
             context_type: "knowledge_base",
             scope: "account",
             access_control: {
               "public_read" => false,
               "public_write" => false,
               "readers" => [{ "type" => "user", "id" => user.id }],
               "writers" => [{ "type" => "user", "id" => user.id }]
             })
    end

    it "allows system access (nil accessor) to read" do
      expect {
        described_class.find_context(account: account, context_id: context.id, accessor: nil)
      }.not_to raise_error
    end

    it "allows system access (nil accessor) to write" do
      expect {
        described_class.update_context(
          account: account,
          context_id: context.id,
          attributes: { name: "Updated" },
          accessor: nil
        )
      }.not_to raise_error
    end
  end
end
