# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ProvisioningCodeDeployment, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:mission).class_name("Ai::Mission") }
    it { is_expected.to belong_to(:node_instance).class_name("::System::NodeInstance") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:repo_url) }
    it { is_expected.to validate_presence_of(:branch) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe "STATUSES" do
    it "includes the M3 lifecycle states" do
      expect(described_class::STATUSES).to include(
        "pending", "cloning", "installing", "starting", "running", "failed", "rolled_back"
      )
    end
  end

  describe "scopes" do
    let(:mission) { create(:ai_mission) }
    let(:node_instance) { create(:system_node_instance) }

    let(:running_row) do
      described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git", branch: "main", status: "running"
      )
    end
    let(:failed_row) do
      described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git", branch: "main", status: "failed",
        last_error: "boom"
      )
    end
    let(:pending_row) do
      described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git", branch: "main", status: "pending"
      )
    end
    let(:rolled_back_row) do
      described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git", branch: "main", status: "rolled_back"
      )
    end

    it "filters by status with .running" do
      running_row
      failed_row
      expect(described_class.running).to contain_exactly(running_row)
    end

    it "filters by status with .failed" do
      running_row
      failed_row
      expect(described_class.failed).to contain_exactly(failed_row)
    end

    it "filters by status with .pending_deploy" do
      pending_row
      running_row
      expect(described_class.pending_deploy).to contain_exactly(pending_row)
    end

    it "filters by status with .rolled_back" do
      rolled_back_row
      running_row
      expect(described_class.rolled_back).to contain_exactly(rolled_back_row)
    end

    it "orders by created_at desc with .recent" do
      older = described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git", branch: "main", status: "running",
        created_at: 1.hour.ago
      )
      newer = described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git", branch: "main", status: "running"
      )
      expect(described_class.recent.to_a.first).to eq(newer)
      expect(described_class.recent.to_a.last).to eq(older)
    end
  end

  describe "defaults" do
    it "defaults branch to 'main' and status to 'pending' from the table" do
      mission = create(:ai_mission)
      node_instance = create(:system_node_instance)
      row = described_class.create!(
        mission: mission, node_instance: node_instance,
        repo_url: "https://example.com/repo.git"
      )
      expect(row.branch).to eq("main")
      expect(row.status).to eq("pending")
    end
  end
end
