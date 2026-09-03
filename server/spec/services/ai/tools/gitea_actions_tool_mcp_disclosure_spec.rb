# frozen_string_literal: true

require "rails_helper"

# IMP-27cc7dceb97b — an MCP tool RESULT is not a private channel.
#
# Ai::Tools::GiteaActionsTool#create_user_token returned `plaintext:` — a
# freshly minted Gitea personal access token — on its MCP result. Same sink
# analysis as badbaef6c (IMP-fa6cf8ee1eb6):
#
#   * Ai::AgentToolBridgeService writes `result_json.to_s.truncate(200)` into
#     `tool_calls_log` (agent_tool_bridge_service.rb:413), which
#     Api::V1::Ai::ConversationsController persists into
#     ai_messages.processing_metadata — durable jsonb, never re-filtered on
#     read. Ai::SensitiveParams cannot intervene: the value is a String and
#     `.filter` returns non-Hash input unchanged;
#   * the FULL json (truncate_result caps at 50 KB) is appended as a
#     role:"tool" message and sent to the model provider on the next turn.
#
# WHY THE SUBSTITUTE DIFFERS FROM THE CI-WORKER SITES. A CI worker token has a
# retrieval path (ci_workers#rotate_token re-mints on demand). A Gitea PAT does
# NOT: Gitea never re-shows it — the tool's own `list_gitea_user_tokens`
# description says "plaintext is never returned by Gitea after creation". So
# there is no honest retrieval path to advertise, and naming a broken recovery
# path would be its own defect. The only two honest options are out-of-band
# delivery or refusal, and this action already HAS the out-of-band channel:
# `set_as_secret`, which writes the PAT straight into a repo's Gitea Actions
# secret store. So the action now REQUIRES that channel and refuses BEFORE
# minting when it is absent — refusing after minting would leave an orphaned,
# unusable PAT on the Gitea account. This is the shape core's
# `bootstrap_disk_image_ci` already holds.
#
# TRUNCATION WINDOW. Unlike the SystemFleetTool CI-worker site, `plaintext`
# began at roughly char 109 of this result (`{"success":true,` 16 +
# `"token_id":42,` 14 + `"token_name":"platform-ci-readonly",` 36 +
# `"scopes":["read:repository"],` 29 + `"plaintext":"` 13) — comfortably inside
# the ~197 usable chars of the 200-char persisted preview — so the
# persisted-row assertion here genuinely discriminates, and it is paired with
# the untruncated provider-bound payload anyway.
#
# Absence is paired with a positive assertion everywhere: an absence-only
# oracle is satisfied by an action that returns nothing and silently breaks
# the feature. The positives here pin that the PAT still REACHED Gitea's
# secret store (argument-matched, so a mutation delivering nil or "" fails),
# and that the refusal branch mints nothing at all.
#
# NOTE ON FIXTURES: every "token" below is a synthetic constant, never a real
# mint. Assertions are on `include?` / `eq`, so RSpec never echoes a needle
# into a failure message.
RSpec.describe "Ai::Tools::GiteaActionsTool MCP-path secret disclosure" do
  # Synthetic, recognisably fake, long enough that an accidental substring
  # match is impossible. NOT key material.
  let(:synthetic_pat) { "zzSyntheticGiteaPatFixtureEEEEEEEEEEEEEEEEEE" }

  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
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
  let(:client) { instance_double(Devops::Git::GiteaApiClient) }

  before do
    allow(::Devops::Git::ApiClient).to receive(:for).with(credential).and_return(client)
  end

  # Production shape, verbatim: the bridge builds the provider-bound json and
  # the tool_calls_log preview; ConversationsController persists that log into
  # ai_messages.processing_metadata.
  #
  # COVERAGE BOUNDARY: this drives the REAL bridge dispatch and the REAL jsonb
  # column, but hand-assembles the tool_calls_log hop between them rather than
  # running #execute_tool_loop against a stubbed LLM. It pins "this tool's
  # result carries no mint", not "no future bridge change can route a result
  # into processing_metadata by some other key".
  def dispatch_and_persist(tool_name, arguments)
    result_json = bridge.dispatch_tool_call(name: tool_name, arguments: arguments)

    tool_calls_log = [ {
      iteration: 1, tool: tool_name, duration_ms: 1,
      result_preview: result_json.to_s.truncate(200)
    } ]

    message = create(:ai_message,
                     agent: agent, role: "assistant",
                     processing_metadata: { model: "spec", tool_calls_log: tool_calls_log })

    [ JSON.parse(result_json).with_indifferent_access,
      result_json,
      ::Ai::Message.find(message.id).processing_metadata.to_json ]
  end

  describe "create_gitea_user_token with out-of-band delivery" do
    before do
      allow(client).to receive(:create_user_token).and_return({
        success: true, token_id: 42, name: "platform-ci-readonly",
        token: synthetic_pat, scopes: %w[read:repository]
      })
      allow(client).to receive(:create_or_update_action_secret).and_return({ success: true })
      allow(client).to receive(:delete_user_token)
    end

    it "delivers the PAT to Gitea without putting it in the result, the provider payload, or the persisted row" do
      result, provider_payload, persisted = dispatch_and_persist(
        "create_gitea_user_token",
        { token_name: "platform-ci-readonly",
          set_as_secret: { owner: "o", repo: "r", secret_name: "PLATFORM_READ_TOKEN" } }
      )

      # Persisted-row first, deliberately: `plaintext` began at ~char 109 of
      # this result, well inside the 200-char preview window, so this assertion
      # genuinely discriminates here (it failed RED). Contrast the
      # SystemFleetTool CI-worker site, where the serializer's two leading
      # UUIDs pushed the mint past the window and only the provider-bound
      # payload could tell correct code from buggy code.
      expect(persisted.include?(synthetic_pat)).to be(false),
        "the persisted ai_messages.processing_metadata carries the minted Gitea PAT"
      expect(provider_payload.include?(synthetic_pat)).to be(false),
        "the role:\"tool\" payload forwarded to the model provider carries the minted Gitea PAT"
      expect(result.to_json.include?(synthetic_pat)).to be(false),
        "the tool result carries the minted Gitea PAT"
      # A prefix is a partial disclosure into the same two durable sinks.
      expect(provider_payload.include?(synthetic_pat[0, 12])).to be(false),
        "the provider-bound payload carries a prefix of the minted Gitea PAT"

      # POSITIVE: the delivery the caller actually needs still happened. The
      # argument matcher is load-bearing — without it, a mutation passing nil
      # or "" as the secret value would leave every absence assertion green
      # while silently breaking the feature.
      expect(result[:success]).to be(true)
      expect(client).to have_received(:create_or_update_action_secret)
        .with("o", "r", "PLATFORM_READ_TOKEN", synthetic_pat)
      expect(result.dig(:set_as_secret, :ok)).to be(true)
      expect(result.dig(:set_as_secret, :secret_name)).to eq("PLATFORM_READ_TOKEN")
      expect(result[:token_id]).to eq(42)
      expect(result[:token_name]).to eq("platform-ci-readonly")
      expect(result[:scopes]).to eq(%w[read:repository])
      # The PAT that was just minted must NOT be cleaned up on the happy path.
      expect(client).not_to have_received(:delete_user_token)
    end
  end

  describe "create_gitea_user_token without a delivery target" do
    it "refuses BEFORE minting, so no orphaned PAT is left on the Gitea account" do
      expect(client).not_to receive(:create_user_token)

      result, provider_payload, persisted = dispatch_and_persist(
        "create_gitea_user_token", { token_name: "platform-ci-readonly" }
      )

      expect(result[:success]).to be(false)
      # POSITIVE half of the refusal: the caller is told, in-band, what to do
      # instead — a bare refusal that strands the caller is not the fix.
      expect(result[:error].to_s).to match(/set_as_secret/)
      # NOTE: no absence-of-needle assertion here on purpose. `create_user_token`
      # is stubbed to never be called in this example, so `synthetic_pat` cannot
      # exist in this scenario at all — a needle check would be vacuous, not
      # reassuring. The property that matters on this branch is "nothing was
      # minted", which the message expectation above pins directly.
      expect(provider_payload).to be_present
      expect(persisted).to include("tool_calls_log")
    end
  end

  describe "create_gitea_user_token when out-of-band delivery fails" do
    before do
      allow(client).to receive(:create_user_token).and_return({
        success: true, token_id: 7, name: "n", token: synthetic_pat, scopes: []
      })
      allow(client).to receive(:create_or_update_action_secret)
        .and_return({ success: false, error: "rejected" })
      allow(client).to receive(:delete_user_token).and_return({ success: true })
    end

    it "reports the failure, still discloses nothing, and revokes the undeliverable PAT" do
      result, provider_payload, persisted = dispatch_and_persist(
        "create_gitea_user_token",
        { token_name: "n", set_as_secret: { owner: "o", repo: "r", secret_name: "X" } }
      )

      expect(persisted.include?(synthetic_pat)).to be(false),
        "the persisted ai_messages row carries the undeliverable Gitea PAT"
      expect(provider_payload.include?(synthetic_pat)).to be(false),
        "the provider-bound payload carries the undeliverable Gitea PAT"

      # POSITIVE: the caller learns delivery failed AND that the mint was
      # cleaned up, rather than silently accumulating a PAT nobody holds.
      expect(result[:success]).to be(false)
      expect(result.dig(:set_as_secret, :ok)).to be(false)
      expect(result.dig(:set_as_secret, :error)).to eq("rejected")
      expect(client).to have_received(:delete_user_token).with(7)
    end
  end
end
