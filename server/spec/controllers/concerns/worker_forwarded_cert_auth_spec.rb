# frozen_string_literal: true

require "rails_helper"

# authenticate_worker_via_forwarded_cert (the no-bearer-token fallback used by
# operator controllers) previously parsed the X-Forwarded-Tls-Client-Cert-Info
# header itself and trusted its CN outright — so a forged Info header (set by a
# client reaching the backend without traversing the mTLS proxy) could
# impersonate any worker, and a forwarded foreign-CA cert was never verified.
# The fix routes it through Security::MtlsTrust.verify_request (the same trust
# path the worker_auth / Internal::* mTLS filters use): it verifies a forwarded
# cert PEM against OUR internal CA (rejecting foreign-CA impersonation) and only
# falls back to the forwarded CN when Traefik's chain-check is authoritative.
RSpec.describe "worker forwarded-cert auth (via MtlsTrust)", type: :controller do
  controller(ApplicationController) do
    def ping = render(json: { worker_id: current_worker&.id })
  end

  let(:account) { create(:account) }
  let(:worker)  { create(:worker, account: account, status: "active") }

  before { routes.draw { get "ping" => "anonymous#ping" } }

  it "authenticates the worker when MtlsTrust verifies the cert (returns its CN)" do
    allow(Security::MtlsTrust).to receive(:verify_request).and_return(worker.node_instance_id)

    get :ping

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["worker_id"]).to eq(worker.id)
  end

  it "REJECTS a forged Info header naming a real worker when MtlsTrust does not verify it" do
    # A client forges the subject header for a real worker's CN, but the cert is
    # not verifiable against our CA (or absent) -> MtlsTrust returns nil.
    @request.headers["X-Forwarded-Tls-Client-Cert-Info"] =
      CGI.escape(%(Subject="CN=#{worker.node_instance_id}"))
    allow(Security::MtlsTrust).to receive(:verify_request).and_return(nil)

    get :ping

    expect(response).to have_http_status(:unauthorized)
  end

  it "does not authenticate when no verifiable cert material is present" do
    allow(Security::MtlsTrust).to receive(:verify_request).and_return(nil)

    get :ping

    expect(response).to have_http_status(:unauthorized)
  end

  it "does not authenticate when MtlsTrust resolves a CN with no matching active worker" do
    allow(Security::MtlsTrust).to receive(:verify_request).and_return(SecureRandom.uuid)

    get :ping

    expect(response).to have_http_status(:unauthorized)
  end
end
