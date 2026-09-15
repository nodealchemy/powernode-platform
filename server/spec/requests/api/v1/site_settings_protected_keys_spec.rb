# frozen_string_literal: true

require "rails_helper"

# IMP-b9998004a8e2 — the REST twin of SiteSettingTool must not write a
# PROTECTED key.
#
# IMP-70db2b60bfb3 made a protected key (registered `protected: true` on
# Ai::Tools::SiteSettingTool, today the one that arms INV-1) writable over MCP
# only through the human-only verb, which parks for a person to confirm in
# their own session. Api::V1::SiteSettingsController still wrote any key
# directly for any admin.access holder, so the rule held on one door only.
#
# Every example asserts the row as well as the status: a refusal that writes
# anyway passes a status-shaped assertion.
RSpec.describe "Api::V1::SiteSettings protected keys", type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, permissions: [ "admin.access" ]) }
  let(:headers) { auth_headers_for(admin) }

  let(:protected_key) { "zz_rest_spec_protected_key" }
  let(:plain_key) { "zz_rest_spec_plain_key" }

  before do
    Ai::Tools::SiteSettingTool.register_key(protected_key, setting_type: "string",
                                                           description: "REST spec protected key", protected: true)
  end

  def expect_protected_refusal
    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include("protected", "site_setting_set_protected")
  end

  describe "PUT /api/v1/site_settings/:id" do
    it "refuses to change a protected key's value" do
      setting = SiteSetting.set(protected_key, "armed-node")

      put "/api/v1/site_settings/#{setting.id}",
          params: { site_setting: { value: "other-node" } }, headers: headers, as: :json

      expect_protected_refusal
      expect(setting.reload.value).to eq("armed-node")
    end

    it "refuses to rename an ordinary row onto a protected key" do
      setting = SiteSetting.set(plain_key, "harmless")

      put "/api/v1/site_settings/#{setting.id}",
          params: { site_setting: { key: protected_key, value: "attacker-node" } }, headers: headers, as: :json

      expect_protected_refusal
      expect(setting.reload.key).to eq(plain_key)
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    it "still updates an ordinary key" do
      setting = SiteSetting.set(plain_key, "before")

      put "/api/v1/site_settings/#{setting.id}",
          params: { site_setting: { value: "after" } }, headers: headers, as: :json

      expect_success_response
      expect(setting.reload.value).to eq("after")
    end
  end

  describe "POST /api/v1/site_settings" do
    it "refuses to create a protected key" do
      post "/api/v1/site_settings",
           params: { site_setting: { key: protected_key, value: "armed-node", setting_type: "string" } },
           headers: headers, as: :json

      expect_protected_refusal
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    # SiteSetting validates key uniqueness case-insensitively, so a case
    # variant squats the protected key: the confirmed human-only write then
    # fails validation and the key can never be armed.
    it "refuses a case variant of a protected key" do
      post "/api/v1/site_settings",
           params: { site_setting: { key: protected_key.upcase, value: "squat", setting_type: "string" } },
           headers: headers, as: :json

      expect_protected_refusal
      expect(SiteSetting.where("LOWER(key) = ?", protected_key).count).to eq(0)
    end
  end

  describe "PUT /api/v1/site_settings/bulk_update" do
    it "still writes a batch of ordinary keys" do
      put "/api/v1/site_settings/bulk_update",
          params: { settings: { plain_key => { value: "written" } } }, headers: headers, as: :json

      expect_success_response
      expect(SiteSetting.find_by(key: plain_key)&.value).to eq("written")
    end

    it "refuses a settings payload that is not an object rather than relying on the action to crash" do
      put "/api/v1/site_settings/bulk_update",
          params: { settings: [ protected_key ] }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
    end

    it "refuses the whole batch before writing any key when one is protected" do
      put "/api/v1/site_settings/bulk_update",
          params: { settings: { plain_key => { value: "written?" }, protected_key => { value: "armed-node" } } },
          headers: headers, as: :json

      expect_protected_refusal
      expect(SiteSetting.find_by(key: protected_key)).to be_nil
      expect(SiteSetting.find_by(key: plain_key)).to be_nil
    end
  end

  describe "DELETE /api/v1/site_settings/:id" do
    # Unset means "not self-hosted" for the INV-1 key, so a delete disarms it
    # as surely as a write.
    it "refuses to delete a protected key" do
      setting = SiteSetting.set(protected_key, "armed-node")

      delete "/api/v1/site_settings/#{setting.id}", headers: headers, as: :json

      expect_protected_refusal
      expect(SiteSetting.find_by(id: setting.id)).to be_present
    end
  end
end
