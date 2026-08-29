# frozen_string_literal: true

require "rails_helper"

# S1 regression cover (IMP-0310b38ef455), ROW-LEVEL oracle.
#
# The sibling spec (authorize_action_halts_spec.rb) asserts the ACTUATOR is
# never invoked, via message expectations on Devops::RegistryService. That is a
# good oracle but it is also a stub: `expect(X).not_to receive(:y)` neuters the
# method, so it can only observe a call that WOULD have happened — it cannot
# observe what the database ends up holding.
#
# These examples close that gap by asserting PERSISTED STATE with the real
# service left in place. A 403 status alone is NOT evidence: the defect this
# task verifies emitted a perfectly clean 403 *while the write committed*
# (Rails does not halt an action on a render; only a filter render or a raise
# halts). Every pre-existing spec for these endpoints asserted only the status
# and stayed green throughout. So each example here pairs the 403 with a
# statement about the row:
#
#   destroy — the row must still EXIST     (uninstall_instance does destroy!)
#   update  — name/configuration unchanged (update_instance writes attributes)
#
# Actions whose actuator is ALREADY broken independently of authorization are
# deliberately NOT used, because a "row unchanged" assertion there holds under
# the mutant too — a vacuous oracle. Verified by running this file against the
# mutant: RegistryService#activate_instance/#deactivate_instance write
# activated_at/deactivated_at and #install_template writes
# devops_integration_template_id, none of which are columns on these tables, so
# all three raise before persisting. Those are real, separate defects.
#
# Non-vacuity is proven by mutation, not by inspection: reverting
# Authentication#authorize_action! to render-without-raise must turn these red.
RSpec.describe "authorize_action! leaves the row untouched", type: :request do
  let(:account) { create(:account) }

  # Authenticated and legitimately able to READ integrations, but holding none
  # of the write permissions the guarded actions require. This is the shape
  # that matters: an authenticated non-privileged caller, not an anonymous one.
  let(:read_only_user) { create(:user, account: account, permissions: [ "integrations.read" ]) }
  let(:headers) { auth_headers_for(read_only_user) }

  let!(:instance) do
    create(:devops_integration_instance,
           account: account,
           name: "zz-row-integrity-fixture",
           status: "active")
  end

  describe "DELETE /api/v1/integrations/instances/:id without integrations.delete" do
    it "returns 403 and the instance row still exists" do
      delete "/api/v1/integrations/instances/#{instance.id}", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(::Devops::IntegrationInstance.exists?(instance.id)).to be(true),
        "the guard rendered 403 but the row was destroyed anyway — authorize_action! did not halt"
    end
  end

  describe "PATCH /api/v1/integrations/instances/:id without integrations.update" do
    it "returns 403 and the instance attributes are unchanged" do
      patch "/api/v1/integrations/instances/#{instance.id}",
            params: { instance: { name: "zz-mutated-by-unauthorized-caller" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(instance.reload.name).to eq("zz-row-integrity-fixture"),
        "the guard rendered 403 but the update committed — authorize_action! did not halt"
    end
  end

  # A SECOND controller from the affected set, to show the fix is in the shared
  # concern rather than in one controller. Both this one and Integrations::
  # InstancesController call authorize_action! with NO `return if performed?`
  # belt-and-braces after it, so the raise is the only thing halting them.
  describe "DELETE /api/v1/devops/integration_instances/:id without devops.integrations.delete" do
    let(:read_only_user) { create(:user, account: account, permissions: [ "devops.integrations.read" ]) }

    it "returns 403 and the instance row still exists" do
      expect {
        delete "/api/v1/devops/integration_instances/#{instance.id}", headers: headers, as: :json
      }.not_to change(::Devops::IntegrationInstance, :count)

      expect(response).to have_http_status(:forbidden)
      expect(::Devops::IntegrationInstance.exists?(instance.id)).to be(true),
        "the guard rendered 403 but the row was destroyed anyway — authorize_action! did not halt"
    end
  end

  # The guard must not merely halt — it must produce the canonical 403 body.
  # A raise with no matching rescue_from would be a 500, which is also "not a
  # write" and would pass every assertion above.
  describe "the 403 body" do
    it "is the canonical forbidden shape, not a swallowed 500" do
      delete "/api/v1/integrations/instances/#{instance.id}", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body["success"]).to be(false)
      expect(response.body).to include("FORBIDDEN")
    end
  end
end
