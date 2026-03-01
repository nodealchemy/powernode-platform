# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::PersistentContext, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:context_record) do
    described_class.create!(
      account: account,
      created_by_user: user,
      name: "Test Context",
      context_type: "knowledge_base",
      scope: "account",
      version: 1,
      context_data: { key: "value" }
    )
  end

  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).optional }
    it { should belong_to(:created_by_user).optional }
    it { should have_many(:context_entries).dependent(:destroy) }
    it { should have_many(:context_access_logs).dependent(:destroy) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject do
      described_class.new(
        account: account,
        name: "Validation Context",
        context_type: "knowledge_base",
        scope: "account",
        version: 1
      )
    end

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:context_type) }
    it { should validate_presence_of(:scope) }
    it { should validate_inclusion_of(:context_type).in_array(described_class::CONTEXT_TYPES) }
    it { should validate_inclusion_of(:scope).in_array(described_class::SCOPES) }

    it 'requires agent for agent-scoped contexts' do
      ctx = described_class.new(
        account: account,
        name: "Agent Context",
        context_type: "agent_memory",
        scope: "agent",
        version: 1
      )
      expect(ctx).not_to be_valid
      expect(ctx.errors[:agent]).to be_present
    end
  end

  # ==========================================
  # Callbacks
  # ==========================================
  describe 'callbacks' do
    it 'generates a context_id before validation' do
      ctx = described_class.create!(
        account: account,
        name: "Auto ID Context",
        context_type: "knowledge_base",
        scope: "account",
        version: 1
      )
      expect(ctx.context_id).to be_present
      expect(ctx.context_id).to start_with("kb_")
    end

    it 'uses mem_ prefix for agent_memory type' do
      agent = create(:ai_agent, account: account)
      ctx = described_class.create!(
        account: account,
        name: "Memory Context",
        context_type: "agent_memory",
        scope: "agent",
        ai_agent_id: agent.id,
        version: 1
      )
      expect(ctx.context_id).to start_with("mem_")
    end

    it 'uses ctx_ prefix for shared_context type' do
      ctx = described_class.create!(
        account: account,
        name: "Shared Context",
        context_type: "shared_context",
        scope: "account",
        version: 1
      )
      expect(ctx.context_id).to start_with("ctx_")
    end

    it 'calculates data_size_bytes on save' do
      context_record
      expect(context_record.data_size_bytes).to be > 0
    end
  end

  # ==========================================
  # public_read?
  # ==========================================
  describe '#public_read?' do
    it 'returns true when access_control has public_read: true' do
      context_record.update!(access_control: { "public_read" => true })
      expect(context_record.public_read?).to be true
    end

    it 'returns true when access_control has public: true' do
      context_record.update!(access_control: { "public" => true })
      expect(context_record.public_read?).to be true
    end

    it 'returns false when access_control is empty' do
      context_record.update!(access_control: {})
      expect(context_record.public_read?).to be false
    end

    it 'returns false when public_read is false' do
      context_record.update!(access_control: { "public_read" => false })
      expect(context_record.public_read?).to be false
    end
  end

  # ==========================================
  # Archive / Unarchive
  # ==========================================
  describe '#archive! and #unarchive!' do
    it 'archives and unarchives the context' do
      context_record.archive!
      expect(context_record.archived?).to be true
      expect(context_record.archived_at).to be_present

      context_record.unarchive!
      expect(context_record.archived?).to be false
      expect(context_record.archived_at).to be_nil
    end
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    it '.active excludes archived and expired contexts' do
      active_ctx = context_record
      archived_ctx = described_class.create!(
        account: account, name: "Archived", context_type: "knowledge_base",
        scope: "account", version: 1, archived_at: Time.current
      )
      expired_ctx = described_class.create!(
        account: account, name: "Expired", context_type: "knowledge_base",
        scope: "account", version: 1, expires_at: 1.day.ago
      )

      active = described_class.where(account: account).active
      expect(active).to include(active_ctx)
      expect(active).not_to include(archived_ctx)
      expect(active).not_to include(expired_ctx)
    end
  end

  # ==========================================
  # accessible_by?
  # ==========================================
  describe '#accessible_by?' do
    it 'returns true for public contexts' do
      context_record.update!(access_control: { "public" => true })
      expect(context_record.accessible_by?("random-id")).to be true
    end

    it 'returns true for the creator' do
      expect(context_record.accessible_by?(user.id, accessor_type: :user)).to be true
    end

    it 'returns true for users in the access list' do
      other_user = create(:user, account: account)
      context_record.update!(access_control: { "users" => [other_user.id] })
      expect(context_record.accessible_by?(other_user.id, accessor_type: :user)).to be true
    end

    it 'returns false for users not in access list' do
      other_user = create(:user, account: account)
      context_record.update!(access_control: { "users" => [] })
      expect(context_record.accessible_by?(other_user.id, accessor_type: :user)).to be false
    end
  end

  # ==========================================
  # Data operations
  # ==========================================
  describe '#read_data' do
    it 'returns full context_data when no key' do
      expect(context_record.read_data).to eq({ "key" => "value" })
    end

    it 'returns nested value with dotted key' do
      context_record.update!(context_data: { "level1" => { "level2" => "deep" } })
      expect(context_record.read_data("level1.level2")).to eq("deep")
    end

    it 'increments access_count' do
      expect { context_record.read_data }.to change { context_record.reload.access_count }.by(1)
    end
  end

  describe '#write_data' do
    it 'writes nested data with dotted key' do
      context_record.write_data("settings.theme", "dark")
      expect(context_record.reload.context_data.dig("settings", "theme")).to eq("dark")
    end
  end

  # ==========================================
  # Statistics
  # ==========================================
  describe '#statistics' do
    it 'returns expected keys' do
      stats = context_record.statistics
      expect(stats).to include(:entry_count, :data_size_bytes, :version, :age_days, :access_count)
    end
  end
end
