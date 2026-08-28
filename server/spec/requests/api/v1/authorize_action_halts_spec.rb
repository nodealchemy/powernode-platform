# frozen_string_literal: true

require "rails_helper"

# S1 regression cover: a permission guard must HALT, not merely render.
#
# Twelve controllers defined a private `authorize_action!` that called
# render_forbidden / render_error from the action body with no `raise` and no
# `return` on the caller. Rails does not halt an action on a render, so the
# guard produced a clean 403 AND the mutation still ran; the resulting
# DoubleRenderError was swallowed by ApiResponse's
# `rescue_from StandardError ... unless performed?`.
#
# These examples assert THE ACTUATOR IS NEVER INVOKED. Asserting only
# `response.status == 403` passes against the defect and is not valid evidence —
# every pre-existing spec for these endpoints did exactly that and stayed green
# while the writes landed.
RSpec.describe "authorize_action! halts before the actuator", type: :request do
  let(:account) { create(:account) }
  let(:unauthorized_user) { create(:user, account: account, permissions: [ "integrations.read" ]) }
  let(:headers) { auth_headers_for(unauthorized_user) }
  let(:instance) { create(:devops_integration_instance, account: account) }

  describe "DELETE /api/v1/integrations/instances/:id without integrations.delete" do
    it "returns 403 AND never calls the uninstall service" do
      expect(::Devops::RegistryService).not_to receive(:uninstall_instance)

      delete "/api/v1/integrations/instances/#{instance.id}", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/integrations/instances/:id/activate without integrations.update" do
    it "returns 403 AND never calls the activate service" do
      expect(::Devops::RegistryService).not_to receive(:activate_instance)

      post "/api/v1/integrations/instances/#{instance.id}/activate", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/integrations/instances without integrations.create" do
    it "returns 403 AND never calls the install service" do
      expect(::Devops::RegistryService).not_to receive(:install_template)

      post "/api/v1/integrations/instances",
           params: { instance: { name: "zz-fixture" } }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
