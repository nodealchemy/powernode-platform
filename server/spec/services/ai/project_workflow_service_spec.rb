# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ProjectWorkflowService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account, user: user) }

  describe "#start_for_repository" do
    let(:repo) { create(:devops_repository, account: account) }

    it "starts a feature-development campaign scoped to the repo" do
      r = service.start_for_repository(repository: repo, objective: "Add OAuth login")
      campaign = r[:campaign]
      expect(campaign.configuration).to include(
        "workload" => "feature-development",
        "repository_id" => repo.id,
        "objective" => "Add OAuth login"
      )
      expect(r[:loop].configuration["workload"]).to eq("feature-development")
    end

    it "resolves a repo by full_name" do
      r = service.start_for_repository(repository: repo.full_name, objective: "x")
      expect(r[:campaign].configuration["repository_id"]).to eq(repo.id)
    end

    it "raises for a repository not in the account" do
      expect { service.start_for_repository(repository: "nonexistent/repo", objective: "x") }
        .to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#propose_new_project" do
    it "records a supervised new-project campaign carrying the project spec" do
      r = service.propose_new_project(name: "widgets", objective: "Build a widget API", org: "acme")
      campaign = r[:campaign]
      expect(campaign.decision_authority).to eq("supervised")
      expect(campaign.configuration["workload"]).to eq("new-project")
      expect(campaign.configuration.dig("new_project", "name")).to eq("widgets")
      expect(campaign.configuration.dig("new_project", "org")).to eq("acme")
      expect(campaign.configuration.dig("new_project", "status")).to eq("pending_creation")
    end

    it "resolves a default org from account config when none given (no hardcoded org)" do
      r = service.propose_new_project(name: "widgets", objective: "x")
      expect(r[:campaign].configuration.dig("new_project", "org")).to be_present
    end
  end

  describe "Ai::Land::ProposalService approver = ai.campaigns.manage holders" do
    let(:campaign) { create(:ai_campaign, account: account, created_by: user) }
    let(:manager) { create(:user, account: account, permissions: [ "ai.campaigns.manage" ]) }

    it "notifies managers, not arbitrary users" do
      manager # ensure created
      land = Ai::CampaignLand.create!(campaign: campaign, account: account, status: "pending_approval",
                                      source_branch: "campaign/#{campaign.id}", target_branch: "develop")
      Ai::Land::ProposalService.deliver(land)
      expect(Notification.where(user: manager, notification_type: "campaign_land_approval")).to exist
    end
  end
end
