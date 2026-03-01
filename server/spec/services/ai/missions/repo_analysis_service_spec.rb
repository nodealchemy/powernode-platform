# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::RepoAnalysisService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:git_provider, :gitea) }
  let(:credential) { create(:git_provider_credential, :gitea, account: account, provider: provider) }
  let(:repository) { create(:git_repository, account: account, credential: credential) }
  let(:mission) { create(:ai_mission, account: account, created_by: user, repository: repository) }
  let(:service) { described_class.new(mission: mission) }

  describe "#analyze!" do
    it "raises error without repository" do
      mission.update_column(:repository_id, nil)
      expect { service.analyze! }.to raise_error(described_class::AnalysisError, /No repository/)
    end

    context "with credentials" do
      let(:mock_client) { instance_double(Devops::Git::GiteaApiClient) }

      before do
        credential # ensure credential exists
        allow(Devops::Git::ApiClient).to receive(:for).and_return(mock_client)
        allow(mock_client).to receive(:get_file_content).and_return(nil)
        allow(mock_client).to receive(:get_repository).and_return({ "default_branch" => "main" })
        allow(mock_client).to receive(:get_tree).and_return({ entries: [] })
        allow(mock_client).to receive(:list_commits).and_return([])
        allow(mock_client).to receive(:list_issues).and_return([])
      end

      it "updates mission with analysis results" do
        service.analyze!
        mission.reload
        expect(mission.analysis_result).to be_a(Hash)
        expect(mission.analysis_result).to have_key("tech_stack")
      end
    end
  end
end
