# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::PrManagementService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:git_provider, :gitea) }
  let(:credential) { create(:git_provider_credential, :gitea, account: account, provider: provider) }
  let(:repository) { create(:git_repository, account: account, credential: credential) }
  let(:mission) { create(:ai_mission, :active, account: account, created_by: user, repository: repository) }
  let(:service) { described_class.new(mission: mission) }
  let(:mock_client) { instance_double(Devops::Git::GiteaApiClient) }

  before do
    allow(Devops::Git::ApiClient).to receive(:for).and_return(mock_client)
  end

  describe "#create_branch!" do
    it "creates a branch and updates mission" do
      allow(mock_client).to receive(:create_branch).and_return({ success: true, branch: "feature/test" })

      service.create_branch!(base: "main", name: "feature/test")
      expect(mission.reload.branch_name).to eq("feature/test")
    end
  end

  describe "#create_pr!" do
    it "creates a PR and updates mission" do
      allow(mock_client).to receive(:create_pull_request).and_return({
        success: true, number: 42, url: "https://gitea.example.com/repo/pulls/42", id: 1
      })

      service.create_pr!(head: "feature/test", base: "main", title: "Test PR", body: "Description")
      mission.reload
      expect(mission.pr_number).to eq(42)
      expect(mission.pr_url).to eq("https://gitea.example.com/repo/pulls/42")
    end
  end

  describe "#merge_pr!" do
    it "merges a PR" do
      allow(mock_client).to receive(:merge_pull_request).and_return({ success: true })

      result = service.merge_pr!(pr_number: 42)
      expect(result[:success]).to be true
    end
  end
end
