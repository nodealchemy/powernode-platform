# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AguiSession, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:user).optional }
    it { should have_many(:agui_events).dependent(:destroy) }
    it { should have_many(:mcp_app_instances).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:ai_agui_session, account: account) }

    it { should validate_presence_of(:thread_id) }
    it { should validate_inclusion_of(:status).in_array(%w[idle running completed error cancelled]) }

    it "is valid with valid attributes" do
      session = build(:ai_agui_session, account: account)
      expect(session).to be_valid
    end

    it "is invalid without a thread_id" do
      session = build(:ai_agui_session, account: account, thread_id: nil)
      expect(session).not_to be_valid
    end

    it "is invalid with an unknown status" do
      session = build(:ai_agui_session, account: account, status: "unknown")
      expect(session).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:idle_session) { create(:ai_agui_session, :idle, account: account) }
    let!(:running_session) { create(:ai_agui_session, :running, account: account) }
    let!(:completed_session) { create(:ai_agui_session, :completed, account: account) }
    let!(:error_session) { create(:ai_agui_session, :error, account: account) }
    let!(:cancelled_session) { create(:ai_agui_session, :cancelled, account: account) }

    it "returns idle sessions" do
      expect(described_class.idle).to include(idle_session)
      expect(described_class.idle).not_to include(running_session)
    end

    it "returns running sessions" do
      expect(described_class.running).to include(running_session)
      expect(described_class.running).not_to include(idle_session)
    end

    it "returns completed sessions" do
      expect(described_class.completed).to include(completed_session)
    end

    it "returns active sessions" do
      active = described_class.active
      expect(active).to include(idle_session, running_session)
      expect(active).not_to include(completed_session, error_session, cancelled_session)
    end

    it "returns sessions by thread" do
      result = described_class.by_thread(idle_session.thread_id)
      expect(result).to include(idle_session)
    end

    it "returns expired sessions" do
      expired = create(:ai_agui_session, :expired, account: account)
      expect(described_class.expired).to include(expired)
      expect(described_class.expired).not_to include(idle_session)
    end
  end

  describe "#start_run!" do
    let(:session) { create(:ai_agui_session, :idle, account: account) }

    it "transitions to running status" do
      session.start_run!
      expect(session.status).to eq("running")
      expect(session.run_id).to be_present
      expect(session.started_at).to be_present
    end

    it "accepts a custom run_id" do
      session.start_run!(run_id: "custom_run_123")
      expect(session.run_id).to eq("custom_run_123")
    end
  end

  describe "#complete_run!" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "transitions to completed status" do
      session.complete_run!
      expect(session.status).to eq("completed")
      expect(session.completed_at).to be_present
    end
  end

  describe "#cancel_run!" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "transitions to cancelled status" do
      session.cancel_run!
      expect(session.status).to eq("cancelled")
      expect(session.completed_at).to be_present
    end
  end

  describe "#error_run!" do
    let(:session) { create(:ai_agui_session, :running, account: account) }

    it "transitions to error status" do
      session.error_run!
      expect(session.status).to eq("error")
      expect(session.completed_at).to be_present
    end
  end

  describe "#increment_sequence!" do
    let(:session) { create(:ai_agui_session, account: account) }

    it "increments the sequence number" do
      expect { session.increment_sequence! }.to change { session.sequence_number }.by(1)
    end

    it "returns the new sequence number" do
      result = session.increment_sequence!
      expect(result).to eq(1)
    end
  end

  describe "#active?" do
    it "returns true for idle sessions" do
      session = build(:ai_agui_session, status: "idle")
      expect(session.active?).to be true
    end

    it "returns true for running sessions" do
      session = build(:ai_agui_session, status: "running")
      expect(session.active?).to be true
    end

    it "returns false for completed sessions" do
      session = build(:ai_agui_session, status: "completed")
      expect(session.active?).to be false
    end
  end

  describe "#expired?" do
    it "returns true when expires_at is in the past" do
      session = build(:ai_agui_session, expires_at: 1.hour.ago)
      expect(session.expired?).to be true
    end

    it "returns false when expires_at is in the future" do
      session = build(:ai_agui_session, expires_at: 1.hour.from_now)
      expect(session.expired?).to be false
    end

    it "returns false when expires_at is nil" do
      session = build(:ai_agui_session, expires_at: nil)
      expect(session.expired?).to be false
    end
  end

  describe "defaults" do
    it "sets default values on create" do
      session = create(:ai_agui_session, account: account)
      expect(session.status).to eq("idle")
      expect(session.state).to eq({})
      expect(session.messages).to eq([])
      expect(session.tools).to eq([])
      expect(session.context).to eq([])
      expect(session.capabilities).to eq({})
      expect(session.sequence_number).to eq(0)
    end
  end
end
