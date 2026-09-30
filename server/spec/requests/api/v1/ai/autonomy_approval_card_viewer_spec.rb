# frozen_string_literal: true

require "rails_helper"

# IMP-08ebabb04b42 — the protected-setting approval card decides whether to show
# the setting's CURRENT value (and the presenter's rendering of both values) by
# asking its viewer has_permission?. The viewer must answer for the SESSION, not
# for the user's own roles: an account-switch session's authority is its
# delegation's scope (Authentication#has_permission?), and a user who holds
# admin.access at home but switched in under a narrower delegation must not read
# the value through the card that the delegation would refuse them anywhere else.
#
# Every endpoint that serializes the card is pinned, because a leak's audience
# is set by the weakest guard on any of them: the list and the detail both sit
# behind ai.agents.read alone (AutonomyController#validate_permissions).
RSpec.describe "Autonomy approvals — the change card answers for the session", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:key) { "zz_card_viewer_key_#{SecureRandom.hex(3)}" }
  let(:user) { create(:user, account: account, permissions: %w[ai.agents.read admin.access]) }

  let(:executor_class) { "Ai::Executors::DeferredToolCall" }
  let!(:approval_request) do
    create(:ai_approval_request, account: account, status: "pending",
                                 request_data: { "executor_class" => executor_class, "params" => {
                                   "tool_class" => "Ai::Tools::SiteSettingTool",
                                   "action" => "site_setting_set_protected",
                                   "tool_params" => { "key" => key, "value" => "new-value" }
                                 } })
  end

  before do
    Ai::Tools::SiteSettingTool.register_key(key, setting_type: "string", description: "card viewer spec", protected: true)
    SiteSetting.register_value_presenter(key) { |value, _viewer| { items: [ { raw: value.to_s } ], omitted: 0 } }
    SiteSetting.set(key, "old-value")
  end

  after { SiteSetting.value_presenters.delete(key) }

  let(:value_keys) { %w[current_value current_value_set presented_new_value presented_current_value] }

  # Role-backed and bounded by the delegator, who really holds what the role grants there.
  def switched_headers(permissions)
    grantor = create(:user, account: other_account, permissions: permissions)
    delegation = create(:account_delegation, account: other_account, delegated_user: user, delegated_by: grantor,
                                             role: grantor.roles.first)
    expect(delegation.effective_permissions).to match_array(permissions) # precondition: the scope is what we say
    payload = { sub: user.id, account_id: other_account.id, primary_account_id: user.account_id,
                delegation_id: delegation.id, type: "access", version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  def list_card(headers)
    get "/api/v1/ai/autonomy/approvals", headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    row = json_response["data"].find { |r| r["id"] == approval_request.id }
    expect(row).to be_present, "the fixture request is not listed"
    row["change_card"]
  end

  def detail_card(headers)
    get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    json_response["data"]["change_card"]
  end

  def cards(headers) = { list: list_card(headers), detail: detail_card(headers) }

  it "shows the values to the user in their own session" do
    cards(auth_headers_for(user)).each do |surface, card|
      expect(card).to include("key" => key, "new_value" => "new-value", "current_value" => "old-value",
                              "current_value_set" => true), "#{surface}: #{card.inspect}"
      expect(card["presented_new_value"]).to be_present, "#{surface}: #{card.inspect}"
      expect(card["presented_current_value"]).to be_present, "#{surface}: #{card.inspect}"
    end
  end

  it "withholds them from the same user under a delegation that does not carry the read permission" do
    cards(switched_headers(%w[ai.agents.read])).each do |surface, card|
      expect(card).to include("tool" => "site_setting", "key" => key, "new_value" => "new-value"),
                      "#{surface}: the card itself must still render"
      value_keys.each do |value_key|
        expect(card).not_to have_key(value_key), "#{surface}: #{value_key} leaked through the delegation"
      end
    end
  end

  it "shows them under a delegation that carries the permission" do
    cards(switched_headers(%w[ai.agents.read admin.access])).each do |surface, card|
      expect(card).to include("current_value" => "old-value", "current_value_set" => true), "#{surface}: #{card.inspect}"
      expect(card["presented_new_value"]).to be_present, "#{surface}: #{card.inspect}"
      expect(card["presented_current_value"]).to be_present, "#{surface}: #{card.inspect}"
    end
  end

  it "keeps the two-rung ladder under a delegation: settings.manage reads the value, only admin.access the presentation" do
    cards(switched_headers(%w[ai.agents.read settings.manage])).each do |surface, card|
      expect(card).to include("current_value" => "old-value"), "#{surface}: #{card.inspect}"
      expect(card).not_to have_key("presented_new_value"), "#{surface}: #{card.inspect}"
      expect(card).not_to have_key("presented_current_value"), "#{surface}: #{card.inspect}"
    end
  end

  # Defence in depth (F5): a card is built only for a parked TOOL CALL. Another
  # executor's request whose params merely name a tool is not one, and gets none.
  context "when the request's operation is not a parked tool call" do
    let(:executor_class) { "Ai::Executors::SomethingElse" }

    it "renders no card on either surface, even to a viewer who could read the value" do
      cards(auth_headers_for(user)).each do |surface, card|
        expect(card).to be_nil, "#{surface}: #{card.inspect}"
      end
    end
  end
end
