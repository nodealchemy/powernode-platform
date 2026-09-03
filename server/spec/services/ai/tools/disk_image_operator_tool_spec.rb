# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DiskImageOperatorTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  let(:gitea_provider) do
    ::Devops::GitProvider.find_or_create_by!(account: account, provider_type: "gitea") do |p|
      p.name = "Gitea"
      p.slug = "gitea-#{SecureRandom.hex(4)}"
      p.api_base_url = "https://git.example.com"
      p.capabilities = { "actions" => true }
    end
  end
  let!(:credential) do
    create(:git_provider_credential,
           account: account,
           provider: gitea_provider,
           is_active: true,
           is_default: true)
  end

  # Seed the ci_worker role so Worker.create_worker! finds it.
  before(:each) do
    Role.find_or_create_by!(name: "ci_worker") do |r|
      r.role_type = "user"
      r.description = "CI worker"
    end
  end

  describe ".definition + permission" do
    it "exposes the disk_image_operator tool name" do
      expect(described_class.definition[:name]).to eq("disk_image_operator")
    end

    it "lists 3 actions" do
      expect(described_class::ACTIONS).to contain_exactly(
        "provision_disk_image_webhook",
        "provision_ci_worker",
        "bootstrap_disk_image_ci"
      )
    end

    it "documents each action" do
      defs = described_class.action_definitions
      described_class::ACTIONS.each do |a|
        expect(defs).to have_key(a), "missing action_definitions[#{a.inspect}]"
      end
    end

    it "requires system.platforms.publish_disk_image" do
      expect(described_class::REQUIRED_PERMISSION).to eq("system.platforms.publish_disk_image")
    end
  end

  describe "provision_disk_image_webhook" do
    # IMP-fa6cf8ee1eb6 — the plaintext used to ride the result here. It no
    # longer does; the retrieval path does instead. Absence is asserted
    # end-to-end (including the persisted ai_messages row) in
    # disk_image_operator_tool_mcp_disclosure_spec.rb.
    it "creates a DiskImageWebhook + returns the URL and the secret retrieval path, not the secret" do
      expect {
        result = tool.execute(params: { action: "provision_disk_image_webhook", label: "main-ci" })
        expect(result[:success]).to be true
        expect(result[:label]).to eq("main-ci")
        expect(result).not_to have_key(:secret_plaintext)
        expect(result[:webhook_id]).to be_present
        expect(result[:webhook_url]).to match(%r{/api/v1/system/webhooks/disk_image/built/[\w-]{36}})
        expect(result[:secret_delivery]).to match(%r{/rotate_secret})
      }.to change(::System::DiskImageWebhook, :count).by(1)
    end

    it "fails when label is blank" do
      result = tool.execute(params: { action: "provision_disk_image_webhook", label: "" })
      expect(result[:success]).to be false
      expect(result[:error]).to eq("label required")
    end

    it "fails on duplicate label within an account" do
      tool.execute(params: { action: "provision_disk_image_webhook", label: "dup" })
      result = tool.execute(params: { action: "provision_disk_image_webhook", label: "dup" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Validation failed/)
    end
  end

  describe "provision_ci_worker" do
    it "creates a Worker with ci_worker role + returns the token retrieval path, not the token" do
      expect {
        result = tool.execute(params: { action: "provision_ci_worker", name: "release-ci" })
        expect(result[:success]).to be true
        expect(result[:name]).to eq("release-ci")
        expect(result).not_to have_key(:token_plaintext)
        expect(result[:worker_id]).to be_present
        expect(result[:roles]).to include("ci_worker")
        expect(result[:token_delivery]).to match(%r{/rotate_token})
      }.to change(::Worker, :count).by(1)
    end

    it "fails when name is blank" do
      result = tool.execute(params: { action: "provision_ci_worker", name: "" })
      expect(result[:success]).to be false
      expect(result[:error]).to eq("name required")
    end
  end

  describe "bootstrap_disk_image_ci" do
    let(:gitea_client) { instance_double(Devops::Git::GiteaApiClient) }

    before do
      allow(::Devops::Git::ApiClient).to receive(:for).with(credential).and_return(gitea_client)
      allow(gitea_client).to receive(:create_or_update_action_secret).and_return({ success: true })
    end

    it "first call: creates webhook + worker + sets all 4 Gitea secrets" do
      expect(gitea_client).to receive(:create_or_update_action_secret)
        .with("powernode", "powernode-system", "POWERNODE_DISK_IMAGE_WEBHOOK_URL", anything)
        .and_return({ success: true })
      expect(gitea_client).to receive(:create_or_update_action_secret)
        .with("powernode", "powernode-system", "POWERNODE_DISK_IMAGE_WEBHOOK_SECRET", anything)
        .and_return({ success: true })
      expect(gitea_client).to receive(:create_or_update_action_secret)
        .with("powernode", "powernode-system", "POWERNODE_CI_WORKER_TOKEN", anything)
        .and_return({ success: true })
      expect(gitea_client).to receive(:create_or_update_action_secret)
        .with("powernode", "powernode-system", "POWERNODE_API_BASE", "http://test-platform.example.com")
        .and_return({ success: true })

      result = tool.execute(params: {
        action: "bootstrap_disk_image_ci",
        owner: "powernode", repo: "powernode-system",
        label: "first-pipeline",
        platform_api_base: "http://test-platform.example.com"
      })

      expect(result[:success]).to be true
      expect(result[:webhook][:action]).to eq("created_new")
      expect(result[:ci_worker][:action]).to eq("created_new")
      expect(result[:gitea_secrets_set].values).to all(eq("ok"))
    end

    it "second call with same label: rotates existing webhook secret + creates worker (different label)" do
      # First bootstrap
      tool.execute(params: {
        action: "bootstrap_disk_image_ci",
        owner: "powernode", repo: "powernode-system",
        label: "rotating-label"
      })

      # Second bootstrap with same label
      expect {
        result = tool.execute(params: {
          action: "bootstrap_disk_image_ci",
          owner: "powernode", repo: "powernode-system",
          label: "rotating-label"
        })
        expect(result[:success]).to be true
        expect(result[:webhook][:action]).to eq("rotated_secret_for_existing")
        expect(result[:ci_worker][:action]).to eq("rotated_token_for_existing")
      }.not_to change(::System::DiskImageWebhook, :count)
    end

    it "fails gracefully when no Gitea credential configured" do
      credential.update!(is_active: false)
      result = tool.execute(params: {
        action: "bootstrap_disk_image_ci",
        owner: "x", repo: "y", label: "test"
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/No active Gitea credential/)
    end

    it "reports per-secret failures via gitea_secrets_set" do
      allow(gitea_client).to receive(:create_or_update_action_secret).and_return({ success: false, error: "rejected" })

      result = tool.execute(params: {
        action: "bootstrap_disk_image_ci",
        owner: "x", repo: "y", label: "fail-test"
      })

      expect(result[:success]).to be true # bootstrap itself succeeded; partial secret failures surface in detail map
      expect(result[:gitea_secrets_set].values).to all(match(/error/))
    end

    context "with create_platform_read_token: true" do
      it "mints a PAT, sets PLATFORM_READ_TOKEN secret, and reports delivery without echoing the token" do
        allow(gitea_client).to receive(:delete_user_token) # idempotent cleanup; may noop
        expect(gitea_client).to receive(:create_user_token)
          .with("plat-test-platform-ci-readonly", scopes: %w[read:repository read:user])
          .and_return({
            success: true, token_id: 99, name: "plat-test-platform-ci-readonly",
            token: "abcdef0123456789abcdef0123456789abcdef01", scopes: %w[read:repository read:user]
          })
        expect(gitea_client).to receive(:create_or_update_action_secret)
          .with("o", "r", "PLATFORM_READ_TOKEN", "abcdef0123456789abcdef0123456789abcdef01")
          .and_return({ success: true })

        result = tool.execute(params: {
          action: "bootstrap_disk_image_ci",
          owner: "o", repo: "r", label: "plat-test",
          create_platform_read_token: true
        })

        expect(result[:success]).to be true
        expect(result[:platform_read_token][:token_id]).to eq(99)
        expect(result[:platform_read_token][:plaintext_set_as_secret]).to eq("PLATFORM_READ_TOKEN")
        expect(result[:gitea_secrets_set]["PLATFORM_READ_TOKEN"]).to eq("ok")
      end

      it "is idempotent: deletes existing token with same name first (delete failure does not block create)" do
        # Prior token exists; delete_user_token may succeed or fail — bootstrap
        # uses `rescue nil` so a missing prior token doesn't break the flow.
        allow(gitea_client).to receive(:delete_user_token).and_raise(StandardError.new("not found"))
        expect(gitea_client).to receive(:create_user_token).and_return({
          success: true, token_id: 100, name: "plat-test-platform-ci-readonly",
          token: "x" * 40, scopes: %w[read:repository read:user]
        })
        allow(gitea_client).to receive(:create_or_update_action_secret).and_return({ success: true })

        result = tool.execute(params: {
          action: "bootstrap_disk_image_ci",
          owner: "o", repo: "r", label: "plat-test",
          create_platform_read_token: true
        })
        expect(result[:success]).to be true
        expect(result[:platform_read_token][:token_id]).to eq(100)
      end

      it "respects platform_read_token_name override" do
        allow(gitea_client).to receive(:delete_user_token)
        expect(gitea_client).to receive(:create_user_token)
          .with("custom-token-name", scopes: %w[read:repository read:user])
          .and_return({ success: true, token_id: 1, name: "custom-token-name", token: "x" * 40, scopes: [] })
        allow(gitea_client).to receive(:create_or_update_action_secret).and_return({ success: true })

        tool.execute(params: {
          action: "bootstrap_disk_image_ci",
          owner: "o", repo: "r", label: "default-label",
          create_platform_read_token: true,
          platform_read_token_name: "custom-token-name"
        })
      end

      it "surfaces token-mint failure in platform_read_token map" do
        allow(gitea_client).to receive(:delete_user_token)
        allow(gitea_client).to receive(:create_user_token).and_return({ success: false, error: "scope insufficient" })
        allow(gitea_client).to receive(:create_or_update_action_secret).and_return({ success: true })

        result = tool.execute(params: {
          action: "bootstrap_disk_image_ci",
          owner: "o", repo: "r", label: "fail-token",
          create_platform_read_token: true
        })
        expect(result[:success]).to be true # the rest of bootstrap still succeeds
        expect(result[:platform_read_token][:error]).to match(/scope insufficient/)
      end
    end
  end
end
