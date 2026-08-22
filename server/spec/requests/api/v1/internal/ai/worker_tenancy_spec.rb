# frozen_string_literal: true

require "rails_helper"

# Tenancy on the LIVE worker→server AI seam (`/api/v1/internal/ai/*`).
#
# Two controllers here loaded tenant rows by bare, caller-supplied id:
#
#   Internal::Ai::CredentialsController#set_credential
#     ::Ai::ProviderCredential.find_by!(id: params[:id])   # renders PLAINTEXT
#   Internal::Ai::ExecutionContextsController#create/#provider_config
#     ::Ai::Agent.find(params[:agent_id])                  # renders the account's
#                                                          # resolved provider +
#                                                          # credential id
#
# The oracle is CROSS-TENANT ACCESS, not status. #decrypt renders the DECRYPTED
# credential hash, so a 200 carrying account B's row IS the disclosure — every
# assertion below inspects the BODY. A status-only check would pass against a
# controller that returned 200 with the victim's API key in it.
#
# The principal is a Worker resolved from the forwarded client-cert CN, and it
# is ACCOUNT-BOUND in production: `workers.node_instance_id` is written only by
# extensions/system/server/lib/tasks/worker_provision.rake, which binds each
# Worker to an operator-supplied account and leaves `is_system` at its column
# default of false. (EnsureSystemWorker also writes that column — but only in
# development, and outside development it REVOKES the sentinel rather than
# writing one.) So the anchor is the worker's own account, with NO exemption
# for the system worker — the same anchor e9352723d adopted, whose property is
# that asserting a worker CN gets you that worker's account and NOTHING beyond
# it, even when the identity is forged. The system-worker examples below assert
# DENIAL for exactly that reason: its CN can be the published constant
# EnsureSystemWorker::DEV_SENTINEL_NODE_ID, so an exemption would be a bypass.
#
# Fetch helpers are `def`s, never `let`s — a memoizing helper would issue one
# request and replay its result, silently passing against unfixed code.
RSpec.describe "Internal AI seam worker tenancy", type: :request do
  # --- Tenant A: the account the account-bound worker belongs to -------------
  let(:account_a)  { create(:account) }
  let(:provider_a) { create(:ai_provider, account: account_a) }
  let!(:credential_a) do
    create(:ai_provider_credential,
      account: account_a, provider: provider_a,
      name: "Tenant A Credential",
      credentials: { "api_key" => tenant_a_key, "model" => "model-a" })
  end

  # --- Tenant B: the victim -------------------------------------------------
  let(:account_b)  { create(:account) }
  let(:provider_b) { create(:ai_provider, account: account_b) }
  let!(:credential_b) do
    create(:ai_provider_credential,
      account: account_b, provider: provider_b,
      name: "Tenant B Secret Credential",
      credentials: { "api_key" => tenant_b_key, "model" => "model-b" })
  end

  # An ACCOUNT-BOUND worker (is_system false) — no legitimate cross-account reach.
  let(:worker_a) { create(:worker, account: account_a, status: "active") }

  # The single global SYSTEM worker — cross-account by design (the live path).
  let(:system_worker) { create(:worker, :system_worker, account: account_a, status: "active") }

  # Plain methods, not constants: a constant defined inside an example group
  # leaks to top level and can be clobbered by another spec file in a
  # defined-order run.
  def tenant_a_key = "sk-tenant-a-legitimate-key"
  def tenant_b_key = "sk-tenant-b-must-never-leak"

  def headers_for(worker)
    {
      "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
      "Content-Type" => "application/json"
    }
  end

  # Every UUID appearing anywhere in the response, regardless of shape.
  def ids_in_body
    response.body.scan(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i).map(&:downcase)
  end

  def decrypt_as(worker, credential)
    post "/api/v1/internal/ai/credentials/#{credential.id}/decrypt", headers: headers_for(worker)
  end

  def provider_config_as(worker, agent_id)
    post "/api/v1/internal/ai/provider_config",
      params: { agent_id: agent_id }.to_json, headers: headers_for(worker)
  end

  def execution_context_as(worker, agent_id)
    post "/api/v1/internal/ai/execution_contexts",
      params: { agent_id: agent_id, input: "hello" }.to_json, headers: headers_for(worker)
  end

  describe "authentication sanity" do
    it "resolves the forwarded CN to the worker (otherwise every denial below is vacuous)" do
      decrypt_as(worker_a, credential_a)

      expect(response).not_to have_http_status(:unauthorized),
        "worker auth did not take effect — the cross-tenant denials would be untested"
    end
  end

  # ===========================================================================
  # CredentialsController#decrypt — renders the DECRYPTED credential hash.
  # ===========================================================================
  describe "POST /api/v1/internal/ai/credentials/:id/decrypt" do
    context "an ACCOUNT-BOUND worker reaching another account's credential" do
      it "does not return tenant B's plaintext API key in the body" do
        decrypt_as(worker_a, credential_b)

        expect(response.body).not_to include(tenant_b_key)
      end

      # FORWARD GUARD, not red-first evidence: #decrypt renders only the
      # credential hash, so this example was already vacuously true before the
      # fix. It exists so that adding an `id:` to the payload cannot silently
      # reintroduce cross-tenant handle disclosure.
      it "does not return tenant B's credential id in the body" do
        decrypt_as(worker_a, credential_b)

        expect(ids_in_body).not_to include(credential_b.id.to_s.downcase)
      end

      it "does not leak tenant B's model or credential name" do
        decrypt_as(worker_a, credential_b)

        # `name` is never rendered by #decrypt, so only the model key is a real
        # oracle here; asserting on the name would be vacuous.
        expect(response.body).not_to include("model-b")
      end
    end

    # ---- POSITIVE CONTROLS: breaking either of these takes down AI chat -----
    context "POSITIVE CONTROL: an account-bound worker decrypting its OWN credential" do
      it "still succeeds AND still receives the plaintext" do
        decrypt_as(worker_a, credential_a)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(tenant_a_key)
      end
    end

    context "the SYSTEM worker reaching another account's credential" do
      # No is_system exemption: its CN may be the published constant
      # EnsureSystemWorker::DEV_SENTINEL_NODE_ID, so exempting it would hand
      # unrestricted cross-account reach to anyone who read the source.
      it "is denied the plaintext too" do
        decrypt_as(system_worker, credential_b)

        expect(response.body).not_to include(tenant_b_key)
      end

      it "still reaches its OWN account's credential" do
        decrypt_as(system_worker, credential_a)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(tenant_a_key)
      end
    end
  end

  # ===========================================================================
  # ExecutionContextsController — leaks the agent's resolved provider +
  # credential id, which the worker then decrypts.
  # ===========================================================================
  describe "POST /api/v1/internal/ai/provider_config" do
    let!(:agent_b) { create(:ai_agent, account: account_b, provider: provider_b, name: "Tenant B Agent") }
    let!(:agent_a) { create(:ai_agent, account: account_a, provider: provider_a, name: "Tenant A Agent") }

    context "an ACCOUNT-BOUND worker naming another account's agent" do
      it "does not disclose tenant B's provider or credential id" do
        provider_config_as(worker_a, agent_b.id)

        expect(ids_in_body).not_to include(credential_b.id.to_s.downcase)
        expect(response.body).not_to include(provider_b.name)
      end
    end

    context "POSITIVE CONTROL: the same worker naming its OWN account's agent" do
      it "still resolves the agent's provider" do
        provider_config_as(worker_a, agent_a.id)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(provider_a.name)
      end
    end

    context "POSITIVE CONTROL: a GLOBAL agent (account_id nil)" do
      # ai_agents.account_id is NULLABLE and global agents are platform-provided
      # and legitimately visible to every account (GloballyScopable#for_account).
      # A naive `where(account_id: worker.account_id)` scope would 404 them and
      # break every chat driven by a global agent — this is the regression guard.
      let!(:global_agent) { create(:ai_agent, :global) }

      it "remains reachable by an account-bound worker" do
        provider_config_as(worker_a, global_agent.id)

        expect(response).to have_http_status(:ok)
      end
    end

    context "the SYSTEM worker naming another account's agent" do
      it "is denied that account's provider too" do
        provider_config_as(system_worker, agent_b.id)

        expect(response.body).not_to include(provider_b.name)
      end
    end
  end

  describe "POST /api/v1/internal/ai/execution_contexts" do
    let!(:agent_b) { create(:ai_agent, account: account_b, provider: provider_b, name: "Tenant B Agent") }

    context "an ACCOUNT-BOUND worker naming another account's agent" do
      it "does not disclose tenant B's agent name, account id, or credential id" do
        execution_context_as(worker_a, agent_b.id)

        expect(response.body).not_to include("Tenant B Agent")
        expect(ids_in_body).not_to include(account_b.id.to_s.downcase)
        expect(ids_in_body).not_to include(credential_b.id.to_s.downcase)
      end
    end

    context "the SYSTEM worker naming another account's agent" do
      it "is denied that agent too" do
        execution_context_as(system_worker, agent_b.id)

        expect(response.body).not_to include("Tenant B Agent")
      end
    end
  end

  # ===========================================================================
  # END-TO-END: the handle provider_config hands out must be one this worker can
  # actually decrypt. Asserting only `:ok` on provider_config cannot see a break
  # where the endpoint returns a credential id belonging to another account —
  # the worker gets a 404 from #decrypt and every chat dies with "Failed to
  # decrypt credentials". This follows the handle through, which is what the
  # live path (LlmProxyClient -> CredentialResolver#fetch_from_server) does.
  # ===========================================================================
  describe "provider_config -> decrypt round trip" do
    def credential_id_from_provider_config
      JSON.parse(response.body).dig("data", "provider_credential_id")
    end

    context "POSITIVE CONTROL: an account-owned agent" do
      let!(:agent_a) { create(:ai_agent, account: account_a, provider: provider_a) }

      it "hands back a handle this worker can decrypt to plaintext" do
        provider_config_as(worker_a, agent_a.id)
        handle = credential_id_from_provider_config
        expect(handle).to be_present, "provider_config resolved no credential at all"

        post "/api/v1/internal/ai/credentials/#{handle}/decrypt", headers: headers_for(worker_a)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(tenant_a_key)
      end
    end

    context "POSITIVE CONTROL: a GLOBAL agent used by this worker's account" do
      # A global agent has no provider of its own, so it must resolve under the
      # USING account (Ai::Agent#using_account). Without that it hands back the
      # seeding account's credential — cross-tenant, and undecryptable here.
      let!(:global_agent) { create(:ai_agent, :global) }

      it "resolves a credential from THIS worker's account, not the seeding one" do
        provider_config_as(worker_a, global_agent.id)
        handle = credential_id_from_provider_config
        expect(handle).to be_present, "global agent resolved no credential at all"

        expect(::Ai::ProviderCredential.find(handle).account_id).to eq(account_a.id)
      end

      it "hands back a handle this worker can decrypt to plaintext" do
        provider_config_as(worker_a, global_agent.id)
        handle = credential_id_from_provider_config

        post "/api/v1/internal/ai/credentials/#{handle}/decrypt", headers: headers_for(worker_a)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(tenant_a_key)
      end
    end
  end

  # ===========================================================================
  # ExecutionContextsController#embedding_config — Account.find(params[:account_id])
  # then renders that account's credential id.
  # ===========================================================================
  describe "GET /api/v1/internal/ai/embedding_config" do
    def embedding_config_as(worker, account_id)
      get "/api/v1/internal/ai/embedding_config",
        params: { account_id: account_id }, headers: headers_for(worker)
    end

    context "an ACCOUNT-BOUND worker naming another account" do
      it "does not disclose tenant B's credential id" do
        embedding_config_as(worker_a, account_b.id)

        expect(ids_in_body).not_to include(credential_b.id.to_s.downcase)
      end
    end

    context "the SYSTEM worker naming another account" do
      it "is denied that account's credential too" do
        embedding_config_as(system_worker, account_b.id)

        expect(ids_in_body).not_to include(credential_b.id.to_s.downcase)
      end
    end
  end
end
