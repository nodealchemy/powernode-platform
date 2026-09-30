# frozen_string_literal: true

require "rails_helper"

# IMP-78bc3b20ee94 — the value-presenter seam. A key's owner registers a
# presenter; the protected-setting approval card shows what it returns NEXT TO
# the raw value, never instead of it, and only to a viewer who could already
# read the setting. A presenter that raises, times out or returns junk costs
# the card its presentation and nothing else.
RSpec.describe "SiteSetting value presenters on the protected-setting approval card" do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, permissions: %w[admin.access ai.agents.read ai.autonomy.approve]) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:key) { "zz_presenter_protected_key_#{SecureRandom.hex(3)}" }
  let(:raw) { %(["11111111-1111-4111-8111-111111111111"]) }

  before do
    Ai::Tools::SiteSettingTool.register_key(key, setting_type: "json", description: "presenter spec", protected: true)
  end

  after { SiteSetting.value_presenters.delete(key) }

  def card_for(viewer, value: raw)
    Ai::Tools::SiteSettingTool.approval_change_card(
      action: "site_setting_set_protected", tool_params: { key: key, value: value }, viewer: viewer
    )
  end

  describe "SiteSetting.present_value" do
    it "is nil for a key with no presenter" do
      expect(SiteSetting.present_value(key, raw)).to be_nil
    end

    it "returns the presenter's rows as string-keyed, string-valued hashes" do
      SiteSetting.register_value_presenter(key) do |value|
        [ { value: JSON.parse(value).first, label: "alpha", detail: "owner: Acme" } ]
      end

      expect(SiteSetting.present_value(key, raw)).to eq(
        [ { "value" => "11111111-1111-4111-8111-111111111111", "label" => "alpha", "detail" => "owner: Acme" } ]
      )
    end

    it "strips control and bidi-override characters and bounds every field" do
      hostile = "evil‮fdp.exe\nsecond line\u0000#{'x' * 500}"
      SiteSetting.register_value_presenter(key) { |_| [ { value: "id", label: hostile, detail: hostile } ] }

      row = SiteSetting.present_value(key, raw).first
      expect(row["label"]).not_to match(/[\p{Cc}\p{Cf}]/)
      expect(row["label"].length).to be <= SiteSetting::PRESENTED_FIELD_LIMIT
      expect(row["label"]).to start_with("evilfdp.exe second line")
      expect(row["detail"].length).to be <= SiteSetting::PRESENTED_FIELD_LIMIT
    end

    it "caps the number of rows and reports nil rather than a truncated list that hides entries" do
      SiteSetting.register_value_presenter(key) do |_|
        Array.new(SiteSetting::PRESENTED_ROW_LIMIT + 1) { |i| { value: "id-#{i}" } }
      end

      expect(SiteSetting.present_value(key, raw)).to be_nil
    end

    it "is nil, not an error, when the presenter raises" do
      SiteSetting.register_value_presenter(key) { |_| raise "boom" }

      expect(SiteSetting.present_value(key, raw)).to be_nil
    end

    it "is nil when the presenter takes longer than the deadline" do
      stub_const("SiteSetting::PRESENTER_DEADLINE", 0.05)
      SiteSetting.register_value_presenter(key) { |_| sleep(1) && [] }

      expect(SiteSetting.present_value(key, raw)).to be_nil
    end

    it "is nil for a malformed return (not a list of hashes carrying a value)" do
      [ "a string", { "value" => "x" }, [ "x" ], [ { label: "no value" } ], nil ].each do |junk|
        SiteSetting.register_value_presenter(key) { |_| junk }
        expect(SiteSetting.present_value(key, raw)).to be_nil, "accepted #{junk.inspect}"
      end
    end
  end

  describe "the approval card" do
    it "carries no presentation when the key has no presenter, and the raw value is unchanged" do
      card = card_for(admin)

      expect(card).to include(new_value: raw)
      expect(card).not_to have_key(:presented_new_value)
      expect(card).not_to have_key(:presented_current_value)
    end

    it "adds the presented value NEXT TO the raw one for a viewer who can read the setting" do
      SiteSetting.set(key, %(["22222222-2222-4222-8222-222222222222"]), setting_type: "json")
      SiteSetting.register_value_presenter(key) { |value| JSON.parse(value).map { |id| { value: id, label: "n-#{id[0, 4]}" } } }

      card = card_for(admin)

      expect(card[:new_value]).to eq(raw)
      expect(card[:presented_new_value]).to eq([ { "value" => "11111111-1111-4111-8111-111111111111", "label" => "n-1111", "detail" => nil } ])
      expect(card[:current_value]).to eq(%(["22222222-2222-4222-8222-222222222222"]))
      expect(card[:presented_current_value].map { |r| r["label"] }).to eq([ "n-2222" ])
    end

    it "does not run the presenter for a viewer who could not read the setting" do
      SiteSetting.register_value_presenter(key) { |_| raise "the presenter must not run for this viewer" }

      expect(card_for(reader)).to include(new_value: raw)
      expect(card_for(reader)).not_to have_key(:presented_new_value)
      expect(card_for(nil)).not_to have_key(:presented_new_value)
    end

    it "falls back to the raw value when the presenter raises" do
      SiteSetting.register_value_presenter(key) { |_| raise "boom" }

      card = card_for(admin)

      expect(card).to include(new_value: raw)
      expect(card).not_to have_key(:presented_new_value)
    end

    it "presents nothing for the current value when the setting is unset" do
      SiteSetting.register_value_presenter(key) { |value| JSON.parse(value).map { |id| { value: id } } }

      card = card_for(admin)

      expect(card[:current_value_set]).to be(false)
      expect(card).not_to have_key(:presented_current_value)
    end
  end

  describe "who receives it over REST", type: :request do
    let!(:approval) do
      SiteSetting.register_value_presenter(key) { |value| JSON.parse(value).map { |id| { value: id, label: "named" } } }
      gate = Ai::AutonomyGate.evaluate(
        action_category: "platform.site_setting.protected_write", executor_class: "Ai::Executors::DeferredToolCall",
        params: { tool_class: "Ai::Tools::SiteSettingTool", action: "site_setting_set_protected",
                  tool_params: { key: key, value: raw } },
        account: account, requested_by: admin
      )
      gate.approval_request
    end

    def card_via(path, user)
      get path, headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok), response.body
      data = json_response["data"]
      data = data.find { |r| r["id"] == approval.id } if data.is_a?(Array)
      data["change_card"]
    end

    [ "/api/v1/ai/autonomy/approvals", nil ].each do |list_path|
      path_for = ->(a) { list_path || "/api/v1/ai/autonomy/approvals/#{a.id}" }

      it "#{list_path ? 'the queue' : 'the detail'} shows the presented value to a setting reader and not to a read-only viewer" do
        expect(approval).to be_pending

        with = card_via(path_for.call(approval), admin)
        without = card_via(path_for.call(approval), reader)

        expect(with).to include("new_value" => raw)
        expect(with["presented_new_value"]).to eq([ { "value" => "11111111-1111-4111-8111-111111111111", "label" => "named", "detail" => nil } ])
        expect(without).to include("new_value" => raw)
        expect(without).not_to have_key("presented_new_value")
        expect(without).not_to have_key("presented_current_value")
      end
    end
  end
end
