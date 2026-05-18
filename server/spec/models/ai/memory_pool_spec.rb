# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::MemoryPool, type: :model do
  let(:account) { create(:account) }
  let(:owner_agent_id) { SecureRandom.uuid }
  let(:pool) do
    create(:ai_memory_pool, account: account, owner_agent_id: owner_agent_id)
  end

  before do
    allow(McpChannel).to receive(:broadcast_to_account)
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "rejects unknown pool_type values" do
      pool.pool_type = "bogus"
      expect(pool).not_to be_valid
      expect(pool.errors[:pool_type]).to be_present
    end

    it "accepts every value in POOL_TYPES" do
      described_class::POOL_TYPES.each do |type|
        pool.pool_type = type
        expect(pool).to be_valid, "expected #{type} to be a valid pool_type"
      end
    end

    it "rejects unknown scope values" do
      pool.scope = "bogus"
      expect(pool).not_to be_valid
      expect(pool.errors[:scope]).to be_present
    end

    it "accepts every value in SCOPES" do
      described_class::SCOPES.each do |s|
        pool.scope = s
        expect(pool).to be_valid, "expected #{s} to be a valid scope"
      end
    end

    it "requires version to be a positive integer" do
      pool.version = 0
      expect(pool).not_to be_valid
      expect(pool.errors[:version]).to be_present
    end

    it "enforces pool_id uniqueness" do
      first = create(:ai_memory_pool, account: account)
      dup = build(:ai_memory_pool, account: account, pool_id: first.pool_id)
      expect(dup).not_to be_valid
      expect(dup.errors[:pool_id]).to be_present
    end

    it "still requires pool_id when callback is bypassed" do
      # generate_pool_id only fires on :create. Once persisted, blanking pool_id
      # surfaces the presence rule.
      pool.pool_id = ""
      expect(pool).not_to be_valid
      expect(pool.errors[:pool_id]).to be_present
    end
  end

  describe "callbacks" do
    describe "before_validation :generate_pool_id" do
      it "auto-generates pool_id when blank" do
        new_pool = build(:ai_memory_pool, account: account, pool_id: nil, pool_type: "shared")
        new_pool.valid?
        expect(new_pool.pool_id).to match(/\Apool_shared_[a-f0-9]{16}\z/)
      end

      it "preserves an explicit pool_id" do
        new_pool = build(:ai_memory_pool, account: account, pool_id: "custom-pool")
        new_pool.valid?
        expect(new_pool.pool_id).to eq("custom-pool")
      end
    end

    describe "before_save :calculate_data_size" do
      it "computes byte size of the serialized data" do
        pool.update!(data: { "foo" => "bar" }, owner_agent_id: owner_agent_id)
        expect(pool.data_size_bytes).to eq(pool.data.to_json.bytesize)
      end
    end

    describe "version increments" do
      it "bumps version when data changes" do
        expect { pool.update!(data: { "k" => "v" }) }.to change { pool.reload.version }.by(1)
      end

      it "does not bump version when only metadata changes" do
        expect { pool.update!(metadata: { "x" => 1 }) }.not_to change { pool.reload.version }
      end
    end
  end

  describe "scopes" do
    let!(:shared)        { create(:ai_memory_pool, account: account, pool_type: "shared") }
    let!(:agent_private) { create(:ai_memory_pool, account: account, pool_type: "agent_private", owner_agent_id: owner_agent_id) }
    let!(:expired)       { create(:ai_memory_pool, :expired, account: account) }
    let!(:persistent)    { create(:ai_memory_pool, :persistent, account: account) }

    it "filters by pool_type via .shared / .agent_private" do
      expect(described_class.shared).to include(shared)
      expect(described_class.shared).not_to include(agent_private)
      expect(described_class.agent_private).to include(agent_private)
    end

    it ".for_agent finds pools by owner" do
      expect(described_class.for_agent(owner_agent_id)).to include(agent_private)
    end

    it ".expired / .active partition by expires_at" do
      expect(described_class.expired).to include(expired)
      expect(described_class.active).not_to include(expired)
      expect(described_class.active).to include(shared)
    end

    it ".persistent matches persist_across_executions" do
      expect(described_class.persistent).to include(persistent)
      expect(described_class.persistent).not_to include(shared)
    end
  end

  describe "#accessible_by?" do
    it "is true for the owner" do
      expect(pool.accessible_by?(owner_agent_id)).to be(true)
    end

    it "is true for agents listed in access_control['agents']" do
      pool.update!(access_control: { "agents" => ["allowed-id"] })
      expect(pool.accessible_by?("allowed-id")).to be(true)
    end

    it "is true when pool is public" do
      pool.update!(access_control: { "public" => true })
      expect(pool.accessible_by?("any-id")).to be(true)
    end

    it "is false otherwise" do
      expect(pool.accessible_by?("not-listed")).to be(false)
    end
  end

  describe "#writable_by?" do
    it "is true for the owner" do
      expect(pool.writable_by?(owner_agent_id)).to be(true)
    end

    it "is true when shared+public" do
      pool.update!(pool_type: "shared", access_control: { "public" => true })
      expect(pool.writable_by?("any-id")).to be(true)
    end

    it "is false for accessible-but-not-owner on non-public pools" do
      pool.update!(pool_type: "agent_private", access_control: { "agents" => ["reader"] })
      expect(pool.writable_by?("reader")).to be(false)
    end
  end

  describe "#write_data + #read_data" do
    it "stores and retrieves a nested key" do
      pool.write_data("foo.bar", 42, agent_id: owner_agent_id)
      expect(pool.read_data("foo.bar", agent_id: owner_agent_id)).to eq(42)
    end

    it "denies write for a non-owner non-public pool" do
      pool.update!(access_control: { "agents" => ["reader"] })
      expect {
        pool.write_data("foo", 1, agent_id: "reader")
      }.to raise_error(ArgumentError, /Only owner can write/)
    end

    it "denies read for a non-accessible agent" do
      expect {
        pool.read_data("foo", agent_id: "stranger")
      }.to raise_error(ArgumentError, /Access denied/)
    end

    it "updates last_accessed_at on read" do
      pool.write_data("x", 1, agent_id: owner_agent_id)
      pool.update_column(:last_accessed_at, 2.hours.ago)

      pool.read_data("x", agent_id: owner_agent_id)
      expect(pool.reload.last_accessed_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#merge_data" do
    it "deep-merges into existing data" do
      pool.write_data("a.b", 1, agent_id: owner_agent_id)
      pool.merge_data({ "a" => { "c" => 2 } }, agent_id: owner_agent_id)
      expect(pool.read_data("a.b", agent_id: owner_agent_id)).to eq(1)
      expect(pool.read_data("a.c", agent_id: owner_agent_id)).to eq(2)
    end
  end

  describe "#delete_data" do
    it "removes a nested key" do
      pool.write_data("foo.bar", "v", agent_id: owner_agent_id)
      pool.delete_data("foo.bar", agent_id: owner_agent_id)
      expect(pool.read_data("foo.bar", agent_id: owner_agent_id)).to be_nil
    end

    it "raises when the key is missing" do
      expect {
        pool.delete_data("nope", agent_id: owner_agent_id)
      }.to raise_error(ArgumentError, /Key not found/)
    end
  end

  describe "#grant_access / #revoke_access" do
    it "adds and removes an agent from access_control" do
      pool.grant_access("new-id")
      expect(pool.reload.access_control["agents"]).to include("new-id")

      pool.revoke_access("new-id")
      expect(pool.reload.access_control["agents"]).not_to include("new-id")
    end

    it "does not duplicate when granting twice" do
      pool.grant_access("dup")
      pool.grant_access("dup")
      expect(pool.reload.access_control["agents"].count("dup")).to eq(1)
    end
  end

  describe "#expired?" do
    it "is false when expires_at is nil" do
      expect(pool.expired?).to be(false)
    end

    it "is true when expires_at is in the past" do
      pool.update!(expires_at: 1.minute.ago)
      expect(pool.expired?).to be(true)
    end

    it "is false when expires_at is in the future" do
      pool.update!(expires_at: 1.hour.from_now)
      expect(pool.expired?).to be(false)
    end
  end

  describe "#statistics" do
    it "reports keys + size + age" do
      pool.write_data("a", 1, agent_id: owner_agent_id)
      pool.write_data("b.c", 2, agent_id: owner_agent_id)

      stats = pool.statistics
      expect(stats[:total_keys]).to eq(3) # a, b, b.c
      expect(stats[:data_size_bytes]).to be > 0
      expect(stats[:version]).to be >= 1
      expect(stats[:age_seconds]).to be >= 0
      expect(stats[:last_access_ago]).to be >= 0
    end
  end

  describe "broadcasts" do
    it "broadcasts on key write" do
      pool.write_data("agent_bulletin.beacon", "alive", agent_id: owner_agent_id)
      expect(McpChannel).to have_received(:broadcast_to_account).with(
        account.id,
        hash_including(type: "memory_pool_key_write", key: "agent_bulletin.beacon", is_bulletin: true)
      )
    end

    it "broadcasts on key delete" do
      pool.write_data("foo", "bar", agent_id: owner_agent_id)
      pool.delete_data("foo", agent_id: owner_agent_id)
      expect(McpChannel).to have_received(:broadcast_to_account).with(
        account.id,
        hash_including(type: "memory_pool_key_delete", key: "foo")
      )
    end
  end
end
