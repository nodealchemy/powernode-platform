# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::RunnerLifecycleService do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, provider_type: "gitea") }
  let(:credential) { create(:git_provider_credential, account: account, provider: provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:service) { described_class.new(account: account) }

  let(:mock_client) do
    instance_double(
      Devops::Git::GiteaApiClient,
      supports_runners?: true
    )
  end

  before do
    allow(Devops::Git::ApiClient).to receive(:for).with(credential).and_return(mock_client)
  end

  describe "#sync_runners" do
    context "with a specific credential" do
      it "syncs runners from the credential" do
        runner_data = [
          { "id" => "1", "name" => "runner-1", "status" => "online", "busy" => false, "labels" => ["ubuntu"], "os" => "linux", "architecture" => "amd64", "version" => "2.0" },
          { "id" => "2", "name" => "runner-2", "status" => "offline", "busy" => false, "labels" => [], "os" => "linux", "architecture" => "arm64", "version" => "2.0" }
        ]
        allow(mock_client).to receive(:list_runners).and_return(runner_data)

        synced = service.sync_runners(credential_id: credential.id)

        expect(synced).to be >= 2
        expect(Devops::GitRunner.where(account: account).count).to be >= 2
      end
    end

    context "with all credentials" do
      it "syncs runners from all active credentials" do
        allow(mock_client).to receive(:list_runners).and_return([])

        synced = service.sync_runners

        expect(synced).to eq(0)
      end
    end

    context "when provider doesn't support runners" do
      before do
        allow(mock_client).to receive(:supports_runners?).and_return(false)
      end

      it "returns 0" do
        synced = service.sync_runners(credential_id: credential.id)

        expect(synced).to eq(0)
      end
    end
  end

  describe "#delete_runner" do
    let(:runner) { create(:git_runner, :online, credential: credential, account: account, repository: repository) }

    context "when deletion succeeds" do
      before do
        allow(mock_client).to receive(:delete_runner).and_return({ success: true })
      end

      it "deletes runner from provider and DB" do
        result = service.delete_runner(runner)

        expect(result[:success]).to be true
        expect(Devops::GitRunner.find_by(id: runner.id)).to be_nil
      end

      it "calls client with correct arguments" do
        service.delete_runner(runner)

        expect(mock_client).to have_received(:delete_runner).with(
          repository.owner, repository.name, runner.external_id, scope: :repo
        )
      end
    end

    context "when deletion fails on provider" do
      before do
        allow(mock_client).to receive(:delete_runner).and_return({ success: false, error: "Not found" })
      end

      it "returns error and keeps local record" do
        result = service.delete_runner(runner)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Not found")
        expect(Devops::GitRunner.find_by(id: runner.id)).to be_present
      end
    end

    context "when credential is unusable" do
      let(:runner) { create(:git_runner, :online, credential: credential, account: account) }

      before do
        allow(credential).to receive(:can_be_used?).and_return(false)
      end

      it "returns error" do
        result = service.delete_runner(runner)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Credential")
      end
    end
  end

  describe "#registration_token" do
    let(:runner) { create(:git_runner, :online, credential: credential, account: account, repository: repository) }

    context "when token retrieval succeeds" do
      before do
        allow(mock_client).to receive(:runner_registration_token).and_return({ token: "ABCD1234", expires_at: nil })
      end

      it "returns the token" do
        result = service.registration_token(runner)

        expect(result[:token]).to eq("ABCD1234")
      end

      it "calls client with correct scope" do
        service.registration_token(runner)

        expect(mock_client).to have_received(:runner_registration_token).with(
          repository.owner, repository.name, scope: :repo
        )
      end
    end

    context "with enterprise scope runner" do
      let(:enterprise_runner) { create(:git_runner, :online, credential: credential, account: account, runner_scope: "enterprise") }

      before do
        allow(mock_client).to receive(:runner_registration_token).and_return({ token: "TOKEN", expires_at: nil })
      end

      it "uses admin scope" do
        service.registration_token(enterprise_runner)

        expect(mock_client).to have_received(:runner_registration_token).with(
          nil, nil, scope: :admin
        )
      end
    end
  end

  describe "#removal_token" do
    let(:runner) { create(:git_runner, :online, credential: credential, account: account, repository: repository) }

    before do
      allow(mock_client).to receive(:runner_removal_token).and_return({ token: "REMOVE123", expires_at: nil })
    end

    it "returns the removal token" do
      result = service.removal_token(runner)

      expect(result[:token]).to eq("REMOVE123")
    end
  end

  describe "#update_labels" do
    let(:runner) { create(:git_runner, :online, credential: credential, account: account, repository: repository, labels: ["old-label"]) }

    context "when update succeeds" do
      before do
        allow(mock_client).to receive(:set_runner_labels).and_return({ success: true, labels: ["new-label", "test"] })
      end

      it "updates labels on provider and locally" do
        result = service.update_labels(runner, ["new-label", "test"])

        expect(result[:success]).to be true
        expect(runner.reload.labels).to eq(["new-label", "test"])
      end
    end

    context "when update fails" do
      before do
        allow(mock_client).to receive(:set_runner_labels).and_return({ success: false, error: "Permission denied" })
      end

      it "returns error and keeps old labels" do
        result = service.update_labels(runner, ["new-label"])

        expect(result[:success]).to be false
        expect(runner.reload.labels).to eq(["old-label"])
      end
    end
  end
end
