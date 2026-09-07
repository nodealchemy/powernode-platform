# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::MemoryTool do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  # These examples exercise the tool's BEHAVIOUR, not its authorization, and
  # construct it the way an in-process system caller does — with no user. Since
  # MemoryTool gained a per-action permission gate (G4), such a caller must opt
  # in EXPLICITLY: a nil user does not imply internal, because an MCP instance
  # principal also arrives with none. Authorization itself is pinned separately
  # in read_gated_tools_action_permission_spec.rb.
  let(:tool) { described_class.new(account: account, agent: agent, internal: true) }
  let(:pool) { create(:ai_memory_pool, account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("memory_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :pool_id, :key)
    end

    it "marks action as required" do
      params = described_class.definition[:parameters]
      expect(params[:action][:required]).to be true
      # pool_id and key are optional in the base definition but
      # required per-action (see action_definitions)
      expect(params[:pool_id][:required]).to be false
      expect(params[:key][:required]).to be false
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.read permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    end
  end

  describe "#execute" do
    context "with read_shared_memory action" do
      it "reads data from the memory pool" do
        allow_any_instance_of(Ai::MemoryPool).to receive(:read_data).with("test.key", agent_id: agent.id).and_return("value")

        result = tool.execute(params: { action: "read_shared_memory", pool_id: pool.pool_id, key: "test.key" })
        expect(result[:success]).to be true
        expect(result[:key]).to eq("test.key")
        expect(result[:value]).to eq("value")
      end
    end

    context "with write_shared_memory action" do
      it "writes data to the memory pool" do
        allow_any_instance_of(Ai::MemoryPool).to receive(:write_data).with("test.key", "new_value", agent_id: agent.id)

        result = tool.execute(params: { action: "write_shared_memory", pool_id: pool.pool_id, key: "test.key", value: "new_value" })
        expect(result[:success]).to be true
        expect(result[:key]).to eq("test.key")
        expect(result[:written]).to be true
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "delete_memory", pool_id: pool.pool_id, key: "test" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "when pool is not found" do
      it "returns error" do
        result = tool.execute(params: { action: "read_shared_memory", pool_id: "nonexistent", key: "test" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when required params are missing" do
        # action is the only required param in the base definition
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters/)
      end
    end
  end

  # IMP-63da66a05a4f — search_memory was the ONLY reader of
  # Ai::AgentShortTermMemory in the tree that did not apply the model's
  # `active` scope, so rows whose TTL had already elapsed were returned as
  # current recall. Filtering readers include Ai::Memory::RouterService
  # #read_short_term and #consolidate!, Api::V1::Ai::TieredMemoryController,
  # and the MaintenanceService consolidation/decay/integrity paths — a sample,
  # not a census, and one of them (TieredMemoryController#consolidate_entry)
  # filters in Ruby via entry.expired? rather than with the scope. The sites
  # that stay deliberately unfiltered are deletes and counts, which want the
  # expired rows.
  #
  # This path is the one that matters most for the omission. Its return value
  # is a TOOL RESULT handed straight back to the model, so an expired row's
  # memory_value blob enters the context window as fact. ttl_seconds is the
  # only expiry mechanism this table has, which makes "expired" a deliberate
  # statement that the content must no longer be relied on.
  #
  # THE ORACLE IS THE KEY SET, never the count. Two rows both match the query
  # here, so "expect(count).to eq(1)" would pass just as happily against a
  # mutant that dropped the LIVE row and kept the expired one — the exact
  # inversion of the bug. Asserting inclusion and exclusion by key pins which
  # row survived.
  describe "search_memory and expired short-term memory" do
    let(:session_id) { SecureRandom.uuid }

    def seed_stm!(key:, expired:)
      # expires_at is set by a before_create callback only when nil, so an
      # explicit past value survives; the :expired trait does the same thing.
      create(
        :ai_agent_short_term_memory,
        account: account, agent: agent, session_id: session_id,
        memory_key: key,
        memory_value: { data: "quota policy body for #{key}" },
        expires_at: expired ? 1.hour.ago : 1.hour.from_now
      )
    end

    def search(query)
      tool.execute(params: { action: "search_memory", query: query })
    end

    def returned_short_term_keys(result)
      result[:results].select { |r| r[:tier] == "short_term" }.map { |r| r[:key] }
    end

    it "serves the live memory and withholds the expired one" do
      seed_stm!(key: "quota_policy_live", expired: false)
      seed_stm!(key: "quota_policy_stale", expired: true)

      result = search("quota_policy")

      expect(result[:success]).to be true
      keys = returned_short_term_keys(result)
      expect(keys).to include("quota_policy_live")
      expect(keys).not_to include("quota_policy_stale")
    end

    # The value is the payload that actually reaches the model — an expired
    # row excluded from the key list but still present in some other field
    # would be no better than not filtering at all.
    it "puts no part of the expired row in the payload handed to the model" do
      seed_stm!(key: "quota_policy_live", expired: false)
      seed_stm!(key: "quota_policy_stale", expired: true)

      result = search("quota_policy")

      expect(result.to_json).to include("quota_policy_live")
      expect(result.to_json).not_to include("quota_policy_stale")
      expect(result.to_json).not_to include("body for quota_policy_stale")
    end

    # A row with no expiry at all is NOT expired. The scope is
    # "expires_at IS NULL OR expires_at > now", and a naive fix written as
    # `where("expires_at > ?", Time.current)` would silently drop these —
    # which is why the task directed using the existing scope rather than
    # hand-writing the predicate.
    #
    # The NULL has to be forced in after the fact, and an earlier draft of this
    # example got that wrong in a way worth recording: passing
    # `expires_at: nil` to create does NOT persist a NULL, because
    # `before_create :set_expiration` is `self.expires_at ||= …` — the `||=`
    # fires precisely in the nil case. That draft persisted an ordinary live
    # row, so it duplicated the example above and would have passed against the
    # very `expires_at > ?` mutant it exists to forbid. update_columns skips
    # callbacks, and the reload assertion below is the PRECONDITION oracle: if
    # the NULL ever stops persisting, this fails loudly instead of going
    # quietly vacuous again.
    it "keeps a row with no expiry set" do
      row = create(
        :ai_agent_short_term_memory,
        account: account, agent: agent, session_id: session_id,
        memory_key: "quota_policy_forever",
        memory_value: { data: "no ttl" }
      )
      row.update_columns(ttl_seconds: nil, expires_at: nil)
      expect(row.reload.expires_at).to be_nil

      expect(returned_short_term_keys(search("quota_policy"))).to include("quota_policy_forever")
    end

    # Matching on the jsonb value, not the key, goes through the same relation;
    # pinning it stops a fix that filters one ILIKE branch and not the other.
    it "applies the filter when the match came from memory_value rather than the key" do
      seed_stm!(key: "unrelated_live", expired: false)
      seed_stm!(key: "unrelated_stale", expired: true)

      keys = returned_short_term_keys(search("policy body"))

      expect(keys).to include("unrelated_live")
      expect(keys).not_to include("unrelated_stale")
    end
  end
end
