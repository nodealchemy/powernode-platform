# frozen_string_literal: true

require "rails_helper"

# Devops::RegistryService wrote and queried attribute names that are not columns
# on devops_integration_instances, so install / activate / deactivate raised
# before persisting and delete_credential's in-use check raised instead of
# running. Authorized callers got a 500 on both the integrations/ and devops/
# facades.
#
# The pre-existing request specs for these endpoints stay green against that,
# because every one of them stubs the actuator out
# (`allow(Devops::RegistryService).to receive(:install_template).and_return(double)`)
# and asserts only the response status. A stubbed actuator cannot raise and
# cannot persist, so those specs say nothing about either.
#
# These examples therefore run the REAL service and assert PERSISTED STATE
# positively. "No longer 500s" would be satisfied by any other failure, so each
# example names the row it expects to find.
RSpec.describe "Devops::RegistryService actuators persist for an authorized caller", type: :request do
  let(:account) { create(:account) }
  let(:template) { create(:devops_integration_template) }

  describe "POST /api/v1/integrations/instances" do
    let(:author) do
      create(:user, account: account, permissions: %w[integrations.read integrations.create])
    end
    let(:headers) { auth_headers_for(author) }

    it "persists an instance linked to the requested template" do
      expect {
        post "/api/v1/integrations/instances",
             params: {
               template_id: template.id,
               instance: { name: "zz-actuator-fixture", slug: "zz-actuator-fixture" }
             },
             headers: headers, as: :json
      }.to change(::Devops::IntegrationInstance, :count).by(1)

      expect(response).to have_http_status(:created)

      instance = ::Devops::IntegrationInstance.find_by(account: account, slug: "zz-actuator-fixture")
      expect(instance).to be_present
      expect(instance.integration_template_id).to eq(template.id)
      expect(instance.name).to eq("zz-actuator-fixture")
      expect(instance.status).to eq("pending")
    end

    it "persists the credential association when one is supplied" do
      credential = create(:devops_integration_credential, account: account)

      post "/api/v1/integrations/instances",
           params: {
             template_id: template.id,
             instance: { name: "zz-actuator-cred", slug: "zz-actuator-cred", credential_id: credential.id }
           },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)

      instance = ::Devops::IntegrationInstance.find_by(account: account, slug: "zz-actuator-cred")
      expect(instance).to be_present
      expect(instance.integration_credential_id).to eq(credential.id)
    end
  end

  describe "POST /api/v1/integrations/instances/:id/activate" do
    let(:operator) do
      create(:user, account: account, permissions: %w[integrations.read integrations.update])
    end
    let(:headers) { auth_headers_for(operator) }
    let!(:instance) do
      create(:devops_integration_instance, account: account, template: template, status: "pending")
    end

    before do
      # The connection probe is remote I/O, not the actuator under test.
      allow(::Devops::ExecutionService).to receive(:build_executor)
        .and_return(instance_double("Devops::BaseExecutor", test_connection: { success: true }))
    end

    it "persists status active" do
      post "/api/v1/integrations/instances/#{instance.id}/activate", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq("active")
    end
  end

  describe "POST /api/v1/integrations/instances/:id/deactivate" do
    let(:operator) do
      create(:user, account: account, permissions: %w[integrations.read integrations.update])
    end
    let(:headers) { auth_headers_for(operator) }
    let!(:instance) do
      create(:devops_integration_instance, account: account, template: template, status: "active")
    end

    it "persists status paused" do
      post "/api/v1/integrations/instances/#{instance.id}/deactivate", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq("paused")
    end
  end

  # Both directions. The in-use check has never actually run — it queried a
  # column that does not exist, which raises rather than returning empty — so
  # one-directional cover would pass a change that refuses every deletion.
  describe "DELETE /api/v1/devops/integration_credentials/:id" do
    let(:operator) do
      create(:user, account: account,
                    permissions: %w[devops.integrations.credentials.read
                                    devops.integrations.credentials.delete])
    end
    let(:headers) { auth_headers_for(operator) }
    let!(:credential) { create(:devops_integration_credential, account: account) }

    context "when the credential is in use by an instance" do
      let!(:instance) do
        create(:devops_integration_instance, account: account, template: template, credential: credential)
      end

      it "refuses the deletion and leaves the credential row in place" do
        delete "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to match(/in use/i)
        expect(::Devops::IntegrationCredential.exists?(credential.id)).to be(true)
      end
    end

    context "when the credential is not in use" do
      it "deletes the credential row" do
        expect {
          delete "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json
        }.to change(::Devops::IntegrationCredential, :count).by(-1)

        expect(response).to have_http_status(:ok)
        expect(::Devops::IntegrationCredential.exists?(credential.id)).to be(false)
      end
    end
  end
end
