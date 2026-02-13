# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevopsBridge::PrContextBuilder, type: :service do
  let(:account) { create(:account) }
  let(:provider) { double("Provider", id: SecureRandom.uuid, provider_type: "github", credentials: credentials_scope) }
  let(:credentials_scope) { double("credentials_scope", active: double(first: credential)) }
  let(:credential) { double("Credential", id: "cred-1") }
  let(:repository) do
    double("Repository",
           name: "my-app",
           full_name: "org/my-app",
           project_id: nil,
           provider: provider,
           credential: credential)
  end

  let(:service) { described_class.new(account: account, repository: repository, pr_number: 42) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "#build" do
    context "when no credential is found" do
      before do
        allow(repository).to receive(:credential).and_return(nil)
        allow(provider).to receive_message_chain(:credentials, :active, :first).and_return(nil)
      end

      it "returns nil" do
        expect(service.build).to be_nil
      end
    end

    context "when provider type is unknown" do
      before do
        allow(provider).to receive(:provider_type).and_return("unknown_provider")
      end

      it "returns nil" do
        expect(service.build).to be_nil
      end
    end

    context "when GitHub API client is available" do
      let(:api_client) { double("GithubApiClient") }
      let(:pr_data) do
        {
          title: "Add feature X",
          description: "Implements feature X",
          author: "dev-user",
          base_branch: "main",
          head_branch: "feature/x",
          changed_files: 5,
          additions: 100,
          deletions: 20
        }
      end

      before do
        allow(Devops::Git::GithubApiClient).to receive(:new).and_return(api_client)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request).and_return(true)
        allow(api_client).to receive(:respond_to?).with(:get_merge_request).and_return(false)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request_diff).and_return(true)
        allow(api_client).to receive(:respond_to?).with(:get_merge_request_diff).and_return(false)
        allow(api_client).to receive(:get_pull_request).and_return(pr_data)
        allow(api_client).to receive(:get_pull_request_diff).and_return("diff content here")
      end

      it "builds context with PR data" do
        result = service.build

        expect(result[:repository_name]).to eq("my-app")
        expect(result[:pr_number]).to eq(42)
        expect(result[:title]).to eq("Add feature X")
        expect(result[:description]).to eq("Implements feature X")
        expect(result[:author]).to eq("dev-user")
        expect(result[:diff]).to eq("diff content here")
        expect(result[:files_changed]).to eq(5)
        expect(result[:additions]).to eq(100)
        expect(result[:deletions]).to eq(20)
      end
    end

    context "when GitLab API client is available" do
      let(:api_client) { double("GitlabApiClient") }
      let(:pr_data) do
        {
          title: "MR Title",
          body: "MR description",
          user: "gitlab-user",
          base: { ref: "main" },
          head: { ref: "feature/y" },
          files_count: 3,
          additions: 50,
          deletions: 10
        }
      end

      before do
        allow(provider).to receive(:provider_type).and_return("gitlab")
        allow(Devops::Git::GitlabApiClient).to receive(:new).and_return(api_client)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request).and_return(false)
        allow(api_client).to receive(:respond_to?).with(:get_merge_request).and_return(true)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request_diff).and_return(false)
        allow(api_client).to receive(:respond_to?).with(:get_merge_request_diff).and_return(true)
        allow(api_client).to receive(:get_merge_request).and_return(pr_data)
        allow(api_client).to receive(:get_merge_request_diff).and_return("gitlab diff")
        allow(repository).to receive(:project_id).and_return("project-1")
      end

      it "builds context using merge request methods" do
        result = service.build

        expect(result[:title]).to eq("MR Title")
        expect(result[:description]).to eq("MR description")
        expect(result[:diff]).to eq("gitlab diff")
      end
    end

    context "when API client class is not defined" do
      before do
        allow(Devops::Git::GithubApiClient).to receive(:new).and_raise(NameError, "uninitialized constant")
      end

      it "returns nil" do
        expect(service.build).to be_nil
      end
    end

    context "when fetching PR data fails" do
      let(:api_client) { double("GithubApiClient") }

      before do
        allow(Devops::Git::GithubApiClient).to receive(:new).and_return(api_client)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request).and_return(true)
        allow(api_client).to receive(:get_pull_request).and_raise(StandardError, "API error")
      end

      it "returns nil" do
        expect(service.build).to be_nil
      end
    end

    context "when fetching diff fails" do
      let(:api_client) { double("GithubApiClient") }
      let(:pr_data) { { title: "Test", description: "test" } }

      before do
        allow(Devops::Git::GithubApiClient).to receive(:new).and_return(api_client)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request).and_return(true)
        allow(api_client).to receive(:respond_to?).with(:get_merge_request).and_return(false)
        allow(api_client).to receive(:respond_to?).with(:get_pull_request_diff).and_return(true)
        allow(api_client).to receive(:get_pull_request).and_return(pr_data)
        allow(api_client).to receive(:get_pull_request_diff).and_raise(StandardError, "Diff error")
      end

      it "returns context with empty diff" do
        result = service.build
        expect(result[:diff]).to eq("")
      end
    end
  end
end
