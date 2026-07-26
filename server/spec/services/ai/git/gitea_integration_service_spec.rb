# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Git::GiteaIntegrationService do
  subject(:service) do
    described_class.new(repository_path: "/tmp/repo", gitea_repository: "powernode/powernode-system")
  end

  # This service is reached from a LIVE endpoint (worktree_sessions_controller's
  # finalize-session-with-PR action). It used to resolve its credential via
  # `Devops::GitCredential`, a model that does not exist — so the first line that
  # touched it raised NameError and every call 500'd. The same mistake had
  # already been found and fixed once in System::ManifestFetchService; this was
  # the second copy, which is why it is pinned here rather than left to review.
  describe "#build_gitea_client" do
    context "when a gitea provider and an active credential exist" do
      let!(:provider)   { create(:git_provider, provider_type: "gitea", api_base_url: "https://git.example.test") }
      let!(:credential) { create(:git_provider_credential, provider: provider, is_active: true, is_default: true) }

      it "resolves through GitProvider + GitProviderCredential and builds a client" do
        expect { service.send(:build_gitea_client) }.not_to raise_error
        expect(service.send(:build_gitea_client)).to be_a(Devops::Git::GiteaApiClient)
      end

      # The regression guard proper: a NameError must never be how this fails.
      it "does not reference a nonexistent credential model" do
        expect(defined?(Devops::GitCredential)).to be_nil
        expect { service.send(:build_gitea_client) }.not_to raise_error
      end
    end

    context "when no gitea provider is configured" do
      it "raises a message an operator can act on, not a NameError" do
        allow(Devops::GitProvider).to receive(:find_by).with(provider_type: "gitea").and_return(nil)

        expect { service.send(:build_gitea_client) }
          .to raise_error(RuntimeError, /No Gitea provider configured/)
      end
    end

    context "when the provider exists but has no active credential" do
      let!(:provider) { create(:git_provider, provider_type: "gitea", api_base_url: "https://git.example.test") }

      it "raises the operator-facing credential message" do
        expect { service.send(:build_gitea_client) }
          .to raise_error(RuntimeError, /No active Gitea credential found/)
      end
    end
  end
end
