# frozen_string_literal: true

require "rails_helper"

# Regression guard for the Authentication concern (sub-part (b) of the auth
# hardenings): an impersonation session must not outlive the impersonator's own
# access. handle_impersonation_jwt_token must re-validate, per request, that the
# impersonator is still active AND still authorized to impersonate — otherwise a
# deactivated/de-authorized impersonator keeps full access for the session window.
RSpec.describe "Impersonator re-validation (Authentication)", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:target) { create(:user, account: account) }
  let(:impersonator) { create(:user, :admin, account: account) }

  def impersonation_headers(session, impersonated)
    payload = {
      type: "impersonation",
      session_id: session.id,
      sub: impersonated.id,
      account_id: impersonated.account_id,
      version: Security::JwtService::CURRENT_TOKEN_VERSION
    }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  # The impersonated user reading their own account — a simple authenticated GET.
  def get_own_account(impersonated, headers)
    get "/api/v1/accounts/#{impersonated.account_id}", headers: headers, as: :json
  end

  context "when the impersonator is active and still authorized" do
    it "allows the impersonated request (not 401)" do
      session = ImpersonationSession.create_session!(impersonator: impersonator, impersonated_user: target)

      get_own_account(target, impersonation_headers(session, target))

      expect(response).to have_http_status(:ok)
    end
  end

  context "when the impersonator has been deactivated after the session started" do
    it "rejects the request with 401 and ends the session" do
      session = ImpersonationSession.create_session!(impersonator: impersonator, impersonated_user: target)
      impersonator.update_column(:status, "inactive")

      get_own_account(target, impersonation_headers(session, target))

      expect(response).to have_http_status(:unauthorized)
      expect(session.reload.active?).to be false
    end
  end

  context "when the impersonator loses impersonate authority after the session started" do
    it "rejects the request with 401 and ends the session" do
      # Cross-account impersonation is allowed only because the impersonator is a
      # system admin; once they lose the admin role they are no longer authorized.
      cross_target = create(:user, account: other_account)
      session = ImpersonationSession.create_session!(impersonator: impersonator, impersonated_user: cross_target)
      impersonator.roles = [] # no longer admin, and not in cross_target's account

      get_own_account(cross_target, impersonation_headers(session, cross_target))

      expect(response).to have_http_status(:unauthorized)
      expect(session.reload.active?).to be false
    end
  end
end
