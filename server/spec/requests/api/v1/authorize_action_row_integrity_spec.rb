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
#   create  — no row is INSERTED           (install_template does save!)
#
# activate/deactivate are deliberately absent: both gate on the same
# `integrations.update` permission the PATCH example already exercises, so a
# third example of that guard would add no oracle.
#
# The create case was originally excluded here: RegistryService#install_template
# wrote a `devops_integration_template_id` attribute that is not a column, so it
# raised before persisting and "no new row" held under the mutant too — a
# vacuous oracle. That actuator defect is fixed (IMP-7b9a31bf8a42), so the
# create case now inserts a row when it reaches the service and is a genuine
# oracle. It is included below.
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

  # create — the mutant reaches install_template, which now really does insert.
  # A valid template_id is essential: without one the service raises
  # TemplateNotFoundError before saving and the oracle goes vacuous again.
  describe "POST /api/v1/integrations/instances without integrations.create" do
    let!(:template) { create(:devops_integration_template) }

    it "returns 403 and no instance row is created" do
      expect {
        post "/api/v1/integrations/instances",
             params: {
               template_id: template.id,
               instance: { name: "zz-row-integrity-create", slug: "zz-row-integrity-create" }
             },
             headers: headers, as: :json
      }.not_to change(::Devops::IntegrationInstance, :count)

      expect(response).to have_http_status(:forbidden)
      expect(::Devops::IntegrationInstance.exists?(slug: "zz-row-integrity-create")).to be(false),
        "the guard rendered 403 but install_template committed — authorize_action! did not halt"
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
