# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExternalAgent, type: :model do
  let(:account) { create(:account) }

  describe "validations" do
    subject { build(:external_agent, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:agent_card_url) }

    it "validates agent_card_url format" do
      agent = build(:external_agent, account: account, agent_card_url: "not-a-url")
      expect(agent).not_to be_valid
      expect(agent.errors[:agent_card_url]).to be_present
    end

    it "validates name uniqueness within account" do
      create(:external_agent, account: account, name: "Test Agent")
      agent = build(:external_agent, account: account, name: "Test Agent")

      expect(agent).not_to be_valid
      expect(agent.errors[:name]).to be_present
    end

    it "validates status" do
      agent = build(:external_agent, account: account, status: "invalid")
      expect(agent).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).optional }
  end

  describe "callbacks" do
    it "generates slug on create" do
      agent = create(:external_agent, account: account, name: "My Test Agent")
      expect(agent.slug).to eq("my-test-agent")
    end

    it "handles duplicate slugs" do
      create(:external_agent, account: account, name: "Test Agent 1", slug: "test-agent")
      # Different name but would generate same base slug
      agent = ExternalAgent.new(account: account, name: "Test Agent", agent_card_url: "https://example.com/agent-card.json")
      agent.save!

      expect(agent.slug).to match(/^test-agent(-\d+)?$/)
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns active agents" do
        active = create(:external_agent, account: account, status: "active")
        create(:external_agent, account: account, status: "inactive")

        expect(described_class.active).to eq([active])
      end
    end

    describe ".with_skill" do
      it "returns agents with specific skill" do
        agent = create(:external_agent, account: account, skills: [
                         { "id" => "test.skill", "name" => "Test" }
                       ])
        create(:external_agent, account: account, skills: [])

        expect(described_class.with_skill({ "id" => "test.skill" })).to include(agent)
      end
    end

    describe ".needs_health_check" do
      it "returns agents needing health check" do
        old_check = create(:external_agent, account: account, last_health_check: 10.minutes.ago)
        create(:external_agent, account: account, last_health_check: 1.minute.ago)

        expect(described_class.needs_health_check).to include(old_check)
      end
    end
  end

  describe "#fetch_agent_card!" do
    let(:agent) { create(:external_agent, account: account, agent_card_url: "https://example.com/.well-known/agent-card.json") }

    context "when successful" do
      before do
        allow(A2a::Client::AgentDiscovery).to receive(:fetch_card).and_return(
          success: true,
          card: {
            "name" => "External Agent",
            "version" => "1.0.0",
            "skills" => [{ "id" => "test.skill", "name" => "Test" }],
            "capabilities" => { "streaming" => true }
          }
        )
      end

      it "updates cached card" do
        expect(agent.fetch_agent_card!).to be true

        agent.reload
        expect(agent.cached_card["name"]).to eq("External Agent")
        expect(agent.card_version).to eq("1.0.0")
        expect(agent.health_status).to eq("healthy")
      end

      it "extracts skills" do
        agent.fetch_agent_card!

        agent.reload
        expect(agent.skills).to be_an(Array)
        expect(agent.skills.first["id"]).to eq("test.skill")
      end
    end

    context "when failed" do
      before do
        allow(A2a::Client::AgentDiscovery).to receive(:fetch_card).and_return(
          success: false,
          error: "Connection refused"
        )
      end

      it "updates health status" do
        expect(agent.fetch_agent_card!).to be false

        agent.reload
        expect(agent.health_status).to eq("unhealthy")
        expect(agent.health_details["error"]).to eq("Connection refused")
      end
    end
  end

  describe "#has_skill?" do
    let(:agent) do
      create(:external_agent, account: account, skills: [
               { "id" => "workflow.execute", "name" => "Execute Workflow" }
             ])
    end

    it "returns true for existing skill" do
      expect(agent.has_skill?("workflow.execute")).to be true
    end

    it "returns false for missing skill" do
      expect(agent.has_skill?("unknown.skill")).to be false
    end
  end

  describe "#record_task_result!" do
    let(:agent) { create(:external_agent, account: account, task_count: 0) }

    it "increments task count" do
      expect { agent.record_task_result!(success: true) }
        .to change { agent.reload.task_count }.by(1)
    end

    it "increments success count on success" do
      expect { agent.record_task_result!(success: true) }
        .to change { agent.reload.success_count }.by(1)
    end

    it "increments failure count on failure" do
      expect { agent.record_task_result!(success: false) }
        .to change { agent.reload.failure_count }.by(1)
    end

    it "updates average response time" do
      agent.record_task_result!(success: true, response_time_ms: 100)
      expect(agent.reload.avg_response_time_ms).to eq(100)

      agent.record_task_result!(success: true, response_time_ms: 200)
      expect(agent.reload.avg_response_time_ms).to eq(150)
    end
  end

  describe "#success_rate" do
    it "returns 0 when no tasks" do
      agent = build(:external_agent, task_count: 0)
      expect(agent.success_rate).to eq(0)
    end

    it "calculates correct rate" do
      agent = build(:external_agent, task_count: 10, success_count: 8)
      expect(agent.success_rate).to eq(80.0)
    end
  end

  describe "#card_fresh?" do
    it "returns true for recent cache" do
      agent = build(:external_agent, card_cached_at: 30.minutes.ago)
      expect(agent.card_fresh?).to be true
    end

    it "returns false for old cache" do
      agent = build(:external_agent, card_cached_at: 2.hours.ago)
      expect(agent.card_fresh?).to be false
    end

    it "returns false for no cache" do
      agent = build(:external_agent, card_cached_at: nil)
      expect(agent.card_fresh?).to be false
    end
  end
end
