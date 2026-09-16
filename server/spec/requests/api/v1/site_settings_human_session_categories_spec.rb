# frozen_string_literal: true

require "rails_helper"

# IMP-d0403597f455 — the site-wide human-session category list is the control
# that decides which parked requests only a person may decide in their own
# session (Ai::Approvals::HumanSessionPolicy#patterns reads it, falling back to
# DEFAULT_CATEGORY_PATTERNS while it is not a list of strings).
#
# It was never registered with SiteSettingTool.register_key, so
# Api::V1::SiteSettingsController#refuse_protected_key_write did not refuse it:
# any settings.manage admin session — an impersonation or an account-switch
# session included — could PUT it to [] and drop the own-session requirement for
# every category that is not separately marked. Same self-unmark shape secreview
# §21 G4 closed for intervention-policy rows.
#
# Registering it PROTECTED is what closes the door: the REST twin refuses it,
# the policy-gated site_setting_set verb refuses it, and the only write path
# left is the human-only site_setting_set_protected, which parks for a person to
# confirm in their own session and runs as that person.
RSpec.describe "Api::V1::SiteSettings and the human-session category list", type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, permissions: [ "admin.access", "settings.manage" ]) }
  let(:headers) { auth_headers_for(admin) }
  let(:key) { Ai::Approvals::HumanSessionPolicy::SETTING_KEY }
  let(:armed) { %w[campaign.* *terminate*] }

  def expect_protected_refusal
    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include("protected", "site_setting_set_protected")
  end

  it "is registered as a protected key owned by core" do
    spec = Ai::Tools::SiteSettingTool.operator_configurable_keys[key]

    expect(spec).not_to be_nil, "#{key} is not registered, so no door can tell it from an ordinary setting"
    expect(spec).to include(protected: true, setting_type: "json")
    expect(Ai::Tools::SiteSettingTool.protected_key?(key)).to be(true)
  end

  it "refuses to shrink the list through the REST door, and the policy keeps reading the armed value" do
    setting = SiteSetting.set(key, armed, setting_type: "json")

    put "/api/v1/site_settings/#{setting.id}",
        params: { site_setting: { value: [].to_json } }, headers: headers, as: :json

    expect_protected_refusal
    expect(SiteSetting.get(key)).to eq(armed)
  end

  it "refuses to create the key from the REST door" do
    post "/api/v1/site_settings",
         params: { site_setting: { key: key, value: [].to_json, setting_type: "json" } },
         headers: headers, as: :json

    expect_protected_refusal
    expect(SiteSetting.find_by(key: key)).to be_nil
  end

  it "refuses to delete the armed list, which disarms as surely as a write" do
    setting = SiteSetting.set(key, armed, setting_type: "json")

    delete "/api/v1/site_settings/#{setting.id}", headers: headers, as: :json

    expect_protected_refusal
    expect(SiteSetting.get(key)).to eq(armed)
  end

  it "refuses to rename an ordinary row onto the key" do
    plain = SiteSetting.set("zz_human_session_spec_plain", "harmless")

    put "/api/v1/site_settings/#{plain.id}",
        params: { site_setting: { key: key, value: [].to_json } }, headers: headers, as: :json

    expect_protected_refusal
    expect(SiteSetting.find_by(key: key)).to be_nil
  end

  it "refuses the WHOLE bulk_update that hides it among ordinary keys" do
    SiteSetting.set(key, armed, setting_type: "json")
    SiteSetting.set("site_name", "Before")

    put "/api/v1/site_settings/bulk_update",
        params: { settings: { "site_name" => { value: "Powernode" }, key => { value: [].to_json } } },
        headers: headers, as: :json

    expect_protected_refusal
    expect(SiteSetting.get(key)).to eq(armed)
    # The refusal is the whole request, not a skip of the protected key: a
    # partial write would mean the caller learns which keys are protected by
    # watching which ones moved.
    expect(SiteSetting.get("site_name")).to eq("Before")
  end
end
