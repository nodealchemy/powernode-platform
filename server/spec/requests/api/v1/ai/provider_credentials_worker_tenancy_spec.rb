# frozen_string_literal: true

require "rails_helper"

# Worker-arm tenancy for Api::V1::Ai::ProviderCredentialsController.
#
# The controller branches every credential lookup on `current_worker`. The human
# arm scopes through `current_user.account`; the worker arm used to load ANY
# credential row by bare id. Composed with the forwarded-CN posture (a worker
# identity asserted by a client-settable header wherever the strip middleware
# does not apply), that let one tenant's worker enumerate and decrypt every
# other tenant's AI provider credentials.
#
# The oracle here is CROSS-TENANT ACCESS, not status: `serialize_credential_detail`
# hands the DECRYPTED credential hash to any `current_worker`, so a 200 carrying
# account B's row is a plaintext key disclosure. Every assertion below therefore
# inspects the BODY — a status-only check would pass against a controller that
# returned 200 with the victim's secret in it.
#
# Fetch helpers are `def`s, never `let`s: a memoizing helper would issue one
# request and replay its result, silently passing against unfixed code.
RSpec.describe "Api::V1::Ai::ProviderCredentialsController worker tenancy", type: :request do
  # --- Tenant A: the account the authenticated worker belongs to -------------
  let(:account_a)    { create(:account) }
  let(:provider_a)   { create(:ai_provider, account: account_a) }
  let!(:credential_a) do
    create(:ai_provider_credential,
      account: account_a, provider: provider_a,
      name: "Tenant A Credential",
      credentials: { "api_key" => tenant_a_key, "model" => "model-a" })
  end

  # --- Tenant B: the victim -------------------------------------------------
  let(:account_b)    { create(:account) }
  let(:provider_b)   { create(:ai_provider, account: account_b) }
  let!(:credential_b) do
    create(:ai_provider_credential,
      account: account_b, provider: provider_b,
      name: "Tenant B Secret Credential",
      credentials: { "api_key" => tenant_b_key, "model" => "model-b" })
  end

  # The worker principal: belongs to account A, resolved from the forwarded
  # client-cert CN (the forgeable posture the finding turns on).
  let(:worker_a) { create(:worker, account: account_a, status: "active") }

  # Plain methods, not constants: a constant defined inside an example group
  # leaks to top level and can be clobbered by another spec file in a
  # defined-order run.
  def tenant_a_key = "sk-tenant-a-legitimate-key"
  def tenant_b_key = "sk-tenant-b-must-never-leak"

  def worker_headers
    {
      "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker_a.node_instance_id}")),
      "Content-Type" => "application/json"
    }
  end

  def body
    JSON.parse(response.body)
  end

  # Every credential id appearing anywhere in the response, regardless of shape.
  def ids_in_body
    response.body.scan(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i).map(&:downcase)
  end

  def get_credential(provider, credential)
    get "/api/v1/ai/providers/#{provider.id}/credentials/#{credential.id}", headers: worker_headers
  end

  def list_credentials(provider)
    get "/api/v1/ai/providers/#{provider.id}/credentials", headers: worker_headers
  end

  def decrypt_credential(credential)
    post "/api/v1/ai/credentials/#{credential.id}/decrypt", headers: worker_headers
  end

  describe "authentication sanity" do
    it "resolves the forwarded CN to the worker (otherwise every denial below is vacuous)" do
      get_credential(provider_a, credential_a)

      expect(response).not_to have_http_status(:unauthorized),
        "worker auth did not take effect — the cross-tenant denials would be untested"
    end
  end

  # ---------------------------------------------------------------------------
  # POSITIVE CONTROL — without this, a denial is indistinguishable from a
  # broken endpoint.
  # ---------------------------------------------------------------------------
  describe "positive control: worker reaching its OWN account's credential" do
    it "returns the credential and its decrypted material on #show" do
      get_credential(provider_a, credential_a)

      expect(response).to have_http_status(:ok)
      credential = body.dig("data", "credential")
      expect(credential["id"]).to eq(credential_a.id)
      expect(credential["name"]).to eq("Tenant A Credential")
      # `serialize_credential_detail` gives workers the decrypted hash — this is
      # the behaviour AiWorkspaceResponseJob#fetch_credentials depends on.
      expect(credential.dig("credentials", "api_key")).to eq(tenant_a_key)
    end

    it "lists its own account's credential on #index" do
      list_credentials(provider_a)

      expect(response).to have_http_status(:ok)
      expect(ids_in_body).to include(credential_a.id)
    end

    it "decrypts its own account's credential" do
      decrypt_credential(credential_a)

      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "credentials", "api_key")).to eq(tenant_a_key)
    end
  end

  # ---------------------------------------------------------------------------
  # THE ORACLE — cross-tenant reach. Body assertions only.
  # ---------------------------------------------------------------------------
  describe "cross-tenant denial: worker of account A against account B's credential" do
    # Each example pins BOTH the body (no disclosure) and the status (the denial
    # came from the tenancy scope, not from an unrelated failure). Without the
    # status assertion an example would pass vacuously if worker auth silently
    # broke and every request 401'd.
    it "does not disclose account B's credential via #show" do
      get_credential(provider_b, credential_b)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(tenant_b_key)
      expect(response.body).not_to include("Tenant B Secret Credential")
      # Not even its existence.
      expect(ids_in_body).not_to include(credential_b.id)
    end

    it "does not disclose account B's plaintext via #decrypt" do
      decrypt_credential(credential_b)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(tenant_b_key)
      expect(body.dig("data", "credentials")).to be_nil
    end

    # NOTE: pointing #index at provider_a proves nothing — apply_credential_filters
    # already narrows by params[:provider_id], so credential_b was absent from that
    # result set even BEFORE the fix. Only pointing it at B's own provider
    # discriminates, so that is the only index denial asserted here.
    it "does not enumerate account B's credentials when #index is pointed at B's provider" do
      list_credentials(provider_b)

      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "credentials")).to eq([])
      expect(ids_in_body).not_to include(credential_b.id)
      expect(response.body).not_to include("Tenant B Secret Credential")
      expect(response.body).not_to include(tenant_b_key)
    end

    # The live worker caller (AiWorkspaceResponseJob#fetch_credentials) always
    # sends default_only+active — exercise the filtered shape too.
    it "does not enumerate account B's credentials under the filters the real worker caller sends" do
      get "/api/v1/ai/providers/#{provider_b.id}/credentials",
        params: { default_only: "true", active: true }, headers: worker_headers

      expect(ids_in_body).not_to include(credential_b.id)
      expect(response.body).not_to include(tenant_b_key)
    end
  end

  # ---------------------------------------------------------------------------
  # The human/UI path is already correctly scoped — guard against regressing it.
  # ---------------------------------------------------------------------------
  describe "human path is unchanged" do
    let(:user_a) { user_with_permissions("ai.providers.read", account: account_a) }

    it "still lets an authorised user read their own account's credential" do
      get "/api/v1/ai/providers/#{provider_a.id}/credentials/#{credential_a.id}",
        headers: auth_headers_for(user_a)

      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "credential", "id")).to eq(credential_a.id)
    end

    it "still denies a user reading another account's credential" do
      get "/api/v1/ai/providers/#{provider_b.id}/credentials/#{credential_b.id}",
        headers: auth_headers_for(user_a)

      expect(response.body).not_to include(tenant_b_key)
      expect(ids_in_body).not_to include(credential_b.id)
    end
  end
end
