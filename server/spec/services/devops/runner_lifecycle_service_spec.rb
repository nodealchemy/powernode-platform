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

  describe "#registration_token_for_scope" do
    context "with repo scope" do
      before do
        allow(mock_client).to receive(:runner_registration_token).and_return({ token: "REPO-TOKEN", expires_at: nil })
      end

      it "returns the client's token result" do
        result = service.registration_token_for_scope(credential: credential, scope: :repo, owner: repository.owner, repo: repository.name)

        expect(result).to eq({ token: "REPO-TOKEN", expires_at: nil })
      end

      it "calls client with correct arguments" do
        service.registration_token_for_scope(credential: credential, scope: :repo, owner: repository.owner, repo: repository.name)

        expect(mock_client).to have_received(:runner_registration_token).with(
          repository.owner, repository.name, scope: :repo
        )
      end
    end

    context "with admin scope" do
      before do
        allow(mock_client).to receive(:runner_registration_token).and_return({ token: "ADMIN-TOKEN", expires_at: nil })
      end

      it "returns the client's token result without owner/repo" do
        result = service.registration_token_for_scope(credential: credential, scope: :admin)

        expect(result).to eq({ token: "ADMIN-TOKEN", expires_at: nil })
      end

      it "calls client with nil owner/repo" do
        service.registration_token_for_scope(credential: credential, scope: :admin)

        expect(mock_client).to have_received(:runner_registration_token).with(
          nil, nil, scope: :admin
        )
      end
    end

    context "when credential is unusable" do
      before do
        allow(credential).to receive(:can_be_used?).and_return(false)
      end

      it "returns an error without calling the client" do
        result = service.registration_token_for_scope(credential: credential, scope: :repo, owner: "acme", repo: "widgets")

        expect(result).to eq({ success: false, error: "Credential not found" })
        expect(Devops::Git::ApiClient).not_to have_received(:for)
      end
    end

    context "when provider doesn't support runners" do
      before do
        allow(mock_client).to receive(:supports_runners?).and_return(false)
      end

      it "returns an error" do
        result = service.registration_token_for_scope(credential: credential, scope: :repo, owner: "acme", repo: "widgets")

        expect(result).to eq({ success: false, error: "Provider does not support runners" })
      end
    end

    context "with repo scope missing owner/repo" do
      it "returns an error without calling the client" do
        expect(mock_client).not_to receive(:runner_registration_token)

        result = service.registration_token_for_scope(credential: credential, scope: :repo)

        expect(result).to eq({ success: false, error: "owner and repo required for repo scope" })
      end
    end

    context "with org scope missing owner" do
      it "returns an error without calling the client" do
        expect(mock_client).not_to receive(:runner_registration_token)

        result = service.registration_token_for_scope(credential: credential, scope: :org)

        expect(result).to eq({ success: false, error: "owner required for org scope" })
      end
    end

    context "with an invalid scope" do
      it "returns an error without calling the client" do
        expect(mock_client).not_to receive(:runner_registration_token)

        result = service.registration_token_for_scope(credential: credential, scope: :bogus)

        expect(result).to eq({ success: false, error: "Invalid scope: bogus" })
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

  # The scope sync was upsert-only: it never reconciled the local set against
  # the set the provider returned, so a row whose upstream runner had vanished
  # survived forever. Fleet builders register EPHEMERAL and Gitea drops each
  # after one job, so every sync that caught one mid-life left a permanent
  # "offline" phantom. Observed 2026-08-07: 51 rows locally, 4 upstream.
  describe "pruning runners that no longer exist upstream" do
    def runner_payload(id, name)
      { "id" => id, "name" => name, "status" => "online", "busy" => false,
        "labels" => [], "os" => "linux", "architecture" => "amd64", "version" => "2.0" }
    end

    def existing_runner(external_id, name, scope: "repository", repo: repository)
      Devops::GitRunner.create!(
        account: account, git_provider_credential_id: credential.id,
        git_repository_id: repo&.id, runner_scope: scope,
        external_id: external_id, name: name, status: "offline", busy: false
      )
    end

    it "deletes a row whose runner is absent from the provider listing" do
      existing_runner("99", "fleet-ephemeral-gone")
      allow(mock_client).to receive(:list_runners).and_return([ runner_payload("1", "runner-1") ])

      service.sync_runners(credential_id: credential.id)

      expect(Devops::GitRunner.where(external_id: "99")).not_to exist
      expect(Devops::GitRunner.where(external_id: "1")).to exist
    end

    # THE load-bearing guard. extract_runners_list degrades ANY unexpected
    # response shape to [] — an auth failure, a changed envelope, a partial
    # outage. Pruning on an empty list would delete every runner in the scope
    # on a transient provider hiccup, which is far worse than the phantoms.
    it "does NOT prune when the provider returns an empty list" do
      existing_runner("99", "fleet-still-real")
      allow(mock_client).to receive(:list_runners).and_return([])

      service.sync_runners(credential_id: credential.id)

      expect(Devops::GitRunner.where(external_id: "99")).to exist
    end

    it "does NOT prune when the listing call raises" do
      existing_runner("99", "fleet-still-real")
      allow(mock_client).to receive(:list_runners).and_raise(StandardError, "provider down")

      service.sync_runners(credential_id: credential.id)

      expect(Devops::GitRunner.where(external_id: "99")).to exist
    end

    # Review finding: ai_runner_dispatches has an FK to git_runners with no
    # on_delete, and Ai::RunnerDispatchService stamps git_runner permanently. So
    # delete_all on a runner that ever ran a job raises InvalidForeignKey, which
    # sync_scope_runners' `rescue StandardError` swallows — the prune silently
    # never runs for exactly the runners that did work, AND the method returns 0
    # instead of the real synced count, disguised as "provider doesn't support
    # runners". My original specs missed it because no fixture had a dispatch.
    it "still prunes a runner that has dispatch history, and does not abort the sync" do
      gone = existing_runner("99", "fleet-had-a-job")
      session  = create(:ai_worktree_session, account: account)
      worktree = create(:ai_worktree, account: account, worktree_session: session)
      create(:ai_runner_dispatch, account: account, git_runner: gone,
                                  worktree: worktree, worktree_session: session, status: "completed")
      allow(mock_client).to receive(:list_runners).and_return([ runner_payload("1", "runner-1") ])

      synced = service.sync_runners(credential_id: credential.id)

      expect(Devops::GitRunner.where(external_id: "99")).not_to exist
      expect(synced).to be >= 1, "sync returned #{synced}; an FK failure was swallowed and reported as a no-op sync"
    end

    # Absence from ONE scope's listing says nothing about another scope.
    it "does NOT prune rows belonging to a different credential" do
      other_cred = create(:git_provider_credential, account: account, provider: provider)
      foreign = Devops::GitRunner.create!(
        account: account, git_provider_credential_id: other_cred.id,
        runner_scope: "repository", external_id: "99", name: "other-cred-runner",
        status: "offline", busy: false
      )
      allow(mock_client).to receive(:list_runners).and_return([ runner_payload("1", "runner-1") ])

      service.sync_runners(credential_id: credential.id)

      expect(Devops::GitRunner.where(id: foreign.id)).to exist
    end
  end
end
