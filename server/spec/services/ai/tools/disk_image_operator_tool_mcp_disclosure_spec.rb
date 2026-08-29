# frozen_string_literal: true

require "rails_helper"

# IMP-fa6cf8ee1eb6 — an MCP tool RESULT is not a private channel.
#
# Ai::AgentToolBridgeService#run_tool_loop does two things with every tool
# result, neither of which the REST twin of these actions does:
#
#   * writes `result_json.truncate(200)` into `tool_calls_log`, which
#     Api::V1::Ai::ConversationsController persists verbatim into
#     ai_messages.processing_metadata — a durable jsonb column that is never
#     re-filtered on read. Ai::SensitiveParams cannot intervene there: the
#     value is a String, and .filter returns non-Hash input unchanged;
#   * appends the FULL json as a `role: "tool"` message, sent to the model
#     provider on the next turn.
#
# So a mint that is correctly "shown once, never stored" over HTTP becomes, on
# this surface, a durable at-rest copy AND an outbound transmission to a
# third-party inference provider. That is the same invariant
# Ai::Tools::AgentAutonomyTool#approve_deferred_operation and
# Ai::Tools::SdwanTool#propose_federation_peer already refuse to cross.
#
# The oracle asserts the persisted ROW, not just the return value, and pairs
# absence-of-plaintext with a positive assertion that the caller still receives
# a usable handle — an absence-only oracle is satisfied by a tool that returns
# nothing and quietly breaks the feature.
#
# COVERAGE BOUNDARY, stated rather than implied: `dispatch_and_persist` calls
# the REAL bridge for the dispatch and the REAL column for the round-trip, but
# it hand-assembles the tool_calls_log hop between them rather than driving
# #execute_tool_loop through a stubbed LLM. So it pins the property "this
# tool's result carries no mint", not "no future bridge change can route a
# result into processing_metadata by some other key". The latter belongs in a
# bridge-level spec, not here.
#
# NOTE ON FIXTURES: the "secrets" here are synthetic constants, never a real
# mint. Nothing in this file prints or interpolates a secret into a failure
# message; assertions are on `include?`, so RSpec never echoes the needle.
RSpec.describe "Ai::Tools::DiskImageOperatorTool MCP-path secret disclosure" do
  # Synthetic, recognisably fake, and long enough that an accidental substring
  # match is impossible. NOT key material.
  let(:synthetic_random) { "zzSyntheticMintFixtureAAAAAAAAAAAAAAAAAAAAAA" }
  let(:synthetic_worker_token) { "swt_zzSyntheticWorkerTokenFixtureBBBBBBBBBBBB" }
  let(:synthetic_pat) { "zzSyntheticGiteaPatFixtureCCCCCCCCCCCCCCCC" }

  # What the extension-side webhook model's create_with_secret! / rotate_secret!
  # build out of the stubbed randomness.
  let(:synthetic_webhook_secret) { "pndis_#{synthetic_random}" }

  let(:account) { create(:account) }
  let(:creator) do
    create(:user, account: account, permissions: %w[system.platforms.publish_disk_image])
  end
  let(:agent) { create(:ai_agent, account: account, creator: creator) }
  let(:bridge) { Ai::AgentToolBridgeService.new(agent: agent, account: account) }

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
           account: account, provider: gitea_provider,
           is_active: true, is_default: true)
  end

  before do
    Role.find_or_create_by!(name: "ci_worker") do |r|
      r.role_type = "user"
      r.description = "CI worker"
    end

    # Pin every mint this tool can perform to a synthetic value so the oracle
    # has a needle. and_call_original first so unrelated callers are untouched.
    allow(SecureRandom).to receive(:urlsafe_base64).and_call_original
    allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return(synthetic_random)
    allow(::Worker).to receive(:generate_secure_token).and_return(synthetic_worker_token)
  end

  # Production shape, verbatim: the bridge builds the role:"tool" content and
  # the tool_calls_log preview; ConversationsController#... persists that log
  # into ai_messages.processing_metadata (conversations_controller.rb:292).
  def dispatch_and_persist(tool_name, arguments)
    result_json = bridge.dispatch_tool_call(name: tool_name, arguments: arguments)

    tool_calls_log = [{
      iteration: 1, tool: tool_name, duration_ms: 1,
      result_preview: result_json.to_s.truncate(200)
    }]

    message = create(:ai_message,
                     agent: agent, role: "assistant",
                     processing_metadata: { model: "spec", tool_calls_log: tool_calls_log })

    [JSON.parse(result_json).with_indifferent_access,
     result_json,
     ::Ai::Message.find(message.id).processing_metadata.to_json]
  end

  describe "provision_disk_image_webhook" do
    it "leaves no minted secret in the persisted ai_messages row, in the provider-bound payload, or in the tool result" do
      result, provider_payload, persisted = dispatch_and_persist(
        "provision_disk_image_webhook", { label: "mcp-disclosure-webhook" }
      )

      expect(persisted.include?(synthetic_webhook_secret)).to be(false),
        "the persisted ai_messages.processing_metadata carries the minted webhook secret"
      expect(provider_payload.include?(synthetic_webhook_secret)).to be(false),
        "the role:\"tool\" payload forwarded to the model provider carries the minted webhook secret"
      expect(result.to_json.include?(synthetic_webhook_secret)).to be(false),
        "the tool result carries the minted webhook secret"
      # A prefix of a secret is still a disclosure into the same two sinks.
      expect(persisted.include?(synthetic_webhook_secret[0, 12])).to be(false),
        "the persisted row carries a prefix of the minted webhook secret"

      # POSITIVE: the caller still gets a usable, non-secret handle.
      expect(result[:success]).to be(true)
      # Reached through the Account association rather than the extension
      # constant, so this core spec names no extension (core-purity).
      webhook = account.system_disk_image_webhooks.find_by(label: "mcp-disclosure-webhook")
      expect(webhook).to be_present
      expect(result[:webhook_id]).to eq(webhook.id)
      expect(result[:label]).to eq("mcp-disclosure-webhook")
      expect(result[:webhook_url]).to match(%r{/api/v1/system/webhooks/disk_image/built/#{webhook.id}})
      # ...and is told, in-band, where the plaintext CAN be obtained.
      expect(result[:secret_delivery].to_s).to match(%r{rotate_secret})
    end
  end

  describe "provision_ci_worker" do
    it "leaves no minted token in the persisted ai_messages row, in the provider-bound payload, or in the tool result" do
      result, provider_payload, persisted = dispatch_and_persist(
        "provision_ci_worker", { name: "mcp-disclosure-worker" }
      )

      expect(persisted.include?(synthetic_worker_token)).to be(false),
        "the persisted ai_messages.processing_metadata carries the minted CI worker token"
      expect(provider_payload.include?(synthetic_worker_token)).to be(false),
        "the role:\"tool\" payload forwarded to the model provider carries the minted CI worker token"
      expect(result.to_json.include?(synthetic_worker_token)).to be(false),
        "the tool result carries the minted CI worker token"
      expect(persisted.include?(synthetic_worker_token[0, 12])).to be(false),
        "the persisted row carries a prefix of the minted CI worker token"

      # POSITIVE: the worker exists, is correctly roled, and is addressable.
      expect(result[:success]).to be(true)
      worker = account.workers.find_by(name: "mcp-disclosure-worker")
      expect(worker).to be_present
      expect(result[:worker_id]).to eq(worker.id)
      expect(result[:roles]).to include("ci_worker")
      expect(result[:token_delivery].to_s).to match(%r{rotate_token})
    end
  end

  describe "bootstrap_disk_image_ci" do
    let(:gitea_client) { instance_double(Devops::Git::GiteaApiClient) }

    before do
      allow(::Devops::Git::ApiClient).to receive(:for).with(credential).and_return(gitea_client)
      allow(gitea_client).to receive(:create_or_update_action_secret).and_return({ success: true })
      allow(gitea_client).to receive(:delete_user_token)
      allow(gitea_client).to receive(:create_user_token).and_return({
        success: true, token_id: 7, name: "bootstrap-label-platform-ci-readonly",
        token: synthetic_pat, scopes: %w[read:repository read:user]
      })
    end

    it "leaks neither the full mints nor their previews, while still reporting delivery" do
      result, provider_payload, persisted = dispatch_and_persist(
        "bootstrap_disk_image_ci",
        { owner: "o", repo: "r", label: "bootstrap-label",
          platform_api_base: "http://platform.example.com",
          create_platform_read_token: true }
      )

      # NOTE ON THE ROW CHECK FOR THIS ACTION. `result_preview` is a 200-char
      # truncation, and bootstrap's `webhook` object alone runs past 200 chars
      # before the previews were ever reached — so the persisted-row assertion
      # is TRUE but not DISCRIMINATING here (it was green against the buggy
      # code too). It is kept because a future result reshuffle could bring
      # material back inside the window, but `provider_payload` — which carries
      # the FULL json to the model provider — is the oracle that actually
      # failed RED for this example. The other two actions put their mint at
      # ~char 120, well inside the window, so their row checks do discriminate.
      [synthetic_webhook_secret, synthetic_worker_token, synthetic_pat].each do |needle|
        expect(persisted.include?(needle)).to be(false),
          "the persisted ai_messages row carries minted material from bootstrap"
        expect(provider_payload.include?(needle)).to be(false),
          "the provider-bound payload carries minted material from bootstrap"
        # 12-char previews were the historical shape here; a preview of a
        # secret is a partial disclosure into the same two durable sinks.
        expect(provider_payload.include?(needle[0, 12])).to be(false),
          "the provider-bound payload carries a preview of minted material from bootstrap"
      end

      # POSITIVE: the delivery the caller actually needs still happened, and is
      # reported — the secrets went to Gitea Actions, out of band.
      expect(result[:success]).to be(true)
      expect(result[:gitea_secrets_set].values).to all(eq("ok"))
      expect(result[:gitea_secrets_set].keys).to include(
        "POWERNODE_DISK_IMAGE_WEBHOOK_URL", "POWERNODE_DISK_IMAGE_WEBHOOK_SECRET",
        "POWERNODE_CI_WORKER_TOKEN", "POWERNODE_API_BASE", "PLATFORM_READ_TOKEN"
      )
      expect(result[:webhook][:id]).to be_present
      expect(result[:webhook][:url]).to match(%r{http://platform.example.com/api/v1/system/webhooks/disk_image/built/})
      expect(result[:ci_worker][:id]).to be_present
      expect(result[:platform_read_token][:token_id]).to eq(7)

      # Out-of-band delivery to Gitea is the ONLY retrieval path bootstrap
      # offers, so the absence half above is only honest if the material
      # actually arrived. Without argument matchers, a mutation passing nil or
      # "" as any of the three secrets would leave every assertion green.
      expect(gitea_client).to have_received(:create_or_update_action_secret)
        .with("o", "r", "POWERNODE_DISK_IMAGE_WEBHOOK_SECRET", synthetic_webhook_secret)
      expect(gitea_client).to have_received(:create_or_update_action_secret)
        .with("o", "r", "POWERNODE_CI_WORKER_TOKEN", synthetic_worker_token)
      expect(gitea_client).to have_received(:create_or_update_action_secret)
        .with("o", "r", "PLATFORM_READ_TOKEN", synthetic_pat)
    end
  end
end
