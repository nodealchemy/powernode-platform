# frozen_string_literal: true

require "rails_helper"

# IMP-78bc3b20ee94 — the value-presenter seam. A key's owner registers a
# presenter; the protected-setting approval card shows what it returns NEXT TO
# the raw value, never instead of it, and only to a viewer holding admin.access
# (the one permission that can complete the approval). A presenter that raises,
# is cancelled by the database deadline, writes, or returns junk costs the card
# its presentation and nothing else.
RSpec.describe "SiteSetting value presenters on the protected-setting approval card" do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, permissions: %w[admin.access ai.agents.read ai.autonomy.approve]) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:settings_manager) { create(:user, account: account, permissions: %w[settings.manage ai.agents.read]) }
  let(:key) { "zz_presenter_protected_key_#{SecureRandom.hex(3)}" }
  let(:id_a) { "11111111-1111-4111-8111-111111111111" }
  let(:raw) { [ id_a ].to_json }

  before do
    Ai::Tools::SiteSettingTool.register_key(key, setting_type: "json", description: "presenter spec", protected: true)
  end

  after { SiteSetting.value_presenters.delete(key) }

  def register(&presenter) = SiteSetting.register_value_presenter(key, &presenter)

  def entry(raw_id, fields: {}, flags: [])
    { raw: raw_id, fields: fields, flags: flags }
  end

  def card_for(viewer, value: raw)
    Ai::Tools::SiteSettingTool.approval_change_card(
      action: "site_setting_set_protected", tool_params: { key: key, value: value }, viewer: viewer
    )
  end

  describe "SiteSetting.present_value" do
    it "is nil for a key with no presenter" do
      expect(SiteSetting.present_value(key, raw)).to be_nil
    end

    it "returns the presenter's items with string keys, and hands the presenter the viewer" do
      seen = nil
      register do |value, viewer|
        seen = viewer
        { items: [ entry(JSON.parse(value).first, fields: { name: "alpha", owner: "Acme" }, flags: [ :other_account ]) ], omitted: 0 }
      end

      presented = SiteSetting.present_value(key, raw, viewer: admin)

      expect(seen).to eq(admin)
      expect(presented).to eq(
        "items" => [ { "raw" => id_a, "fields" => { "name" => "alpha", "owner" => "Acme" }, "flags" => [ "other_account" ] } ],
        "omitted" => 0
      )
    end

    it "keeps tenant text in ONE field: separators, quotes, parens and a fake id cannot start another row" do
      hostile = "evil\u{2028}second\u{2029}third\u{00A0}nbsp \u{201C}quote\u{201D} (owner account: Mine) 22222222-2222-4222-8222-222222222222" \
                "\u{202E}fdp\u0000\n#{'x' * 500}"
      register { |_| { items: [ entry(id_a, fields: { name: hostile }) ], omitted: 0 } }

      presented = SiteSetting.present_value(key, raw)
      name = presented["items"].first["fields"]["name"]

      expect(presented["items"].size).to eq(1)
      expect(name).not_to match(/[\p{C}\p{Z}&&[^ ]]/)
      expect(name).to start_with("evil second third nbsp")
      expect(name).to include("(owner account: Mine)") # still inside the one name field, which the client labels itself
      expect(name.length).to be <= SiteSetting::PRESENTED_FIELD_LIMIT
      expect(presented["items"].first["fields"].keys).to eq([ "name" ])
    end

    it "sanitizes the raw entry too, and bounds it" do
      register { |_| { items: [ entry("#{id_a}\u{2028}#{'y' * 400}") ], omitted: 0 } }

      raw_out = SiteSetting.present_value(key, raw)["items"].first["raw"]

      expect(raw_out).not_to match(/[\p{C}\p{Z}&&[^ ]]/)
      expect(raw_out.length).to be <= SiteSetting::PRESENTED_RAW_LIMIT
    end

    it "caps the items and counts the rest as omitted" do
      register { |_| { items: Array.new(SiteSetting::PRESENTED_ROW_LIMIT + 3) { |i| entry("id-#{i}") }, omitted: 4 } }

      presented = SiteSetting.present_value(key, raw)

      expect(presented["items"].size).to eq(SiteSetting::PRESENTED_ROW_LIMIT)
      expect(presented["omitted"]).to eq(7)
    end

    it "is nil, not an error, when the presenter raises" do
      register { |_| raise "boom" }

      expect(SiteSetting.present_value(key, raw)).to be_nil
    end

    it "cancels a slow query at the database and falls back, leaving the connection clean" do
      stub_const("SiteSetting::PRESENTER_STATEMENT_TIMEOUT_MS", 100)
      before_setting = SiteSetting.connection.select_value("SHOW statement_timeout")
      register do |_|
        SiteSetting.connection.execute("SELECT pg_sleep(3)")
        { items: [ entry(id_a) ], omitted: 0 }
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      presented = SiteSetting.present_value(key, raw)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(presented).to be_nil
      expect(elapsed).to be < 2.0
      expect(SiteSetting.connection.select_value("SELECT 1")).to eq(1)
      expect(SiteSetting.connection.select_value("SHOW statement_timeout")).to eq(before_setting)
    end

    it "runs the presenter read-only: a write is refused, nothing persists, and the card falls back" do
      register do |_|
        SiteSetting.connection.execute("INSERT INTO site_settings (id, key, value, setting_type, is_public, created_at, updated_at) " \
                                       "VALUES (gen_random_uuid(), 'zz_written_by_presenter', 'x', 'string', false, now(), now())")
        { items: [ entry(id_a) ], omitted: 0 }
      end

      expect(SiteSetting.present_value(key, raw)).to be_nil
      expect(SiteSetting.find_by(key: "zz_written_by_presenter")).to be_nil
    end

    it "rolls the presenter's transaction back and leaves the caller's setting untouched" do
      expect(SiteSetting.connection.select_value("SHOW transaction_read_only")).to eq("off")
      register { |_| { items: [ entry(id_a) ], omitted: 0 } }

      SiteSetting.present_value(key, raw)

      expect(SiteSetting.connection.select_value("SHOW transaction_read_only")).to eq("off")
    end

    it "is nil for a malformed return" do
      junk = [
        "a string", [ entry(id_a) ], nil, { items: "x" }, { items: [ "x" ] }, { items: [ { fields: {} } ] },
        { items: [ { raw: id_a, fields: "x" } ] }, { items: [ { raw: id_a, fields: { "Bad Key!" => "x" } } ] },
        { items: [ { raw: id_a, flags: "x" } ] }, { items: [ { raw: id_a, flags: [ "Not A Flag" ] } ] },
        { items: [ entry(id_a) ], omitted: -1 }, { items: [ entry(id_a) ], omitted: "many" }
      ]
      junk.each do |value|
        register { |_| value }
        expect(SiteSetting.present_value(key, raw)).to be_nil, "accepted #{value.inspect}"
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

    it "adds the presented value NEXT TO the raw one for an admin.access holder" do
      SiteSetting.set(key, %(["22222222-2222-4222-8222-222222222222"]), setting_type: "json")
      register { |value, _| { items: JSON.parse(value).map { |id| entry(id, fields: { name: "n-#{id[0, 4]}" }) }, omitted: 0 } }

      card = card_for(admin)

      expect(card[:new_value]).to eq(raw)
      expect(card[:presented_new_value]["items"].first).to include("raw" => id_a, "fields" => { "name" => "n-1111" })
      expect(card[:current_value]).to eq(%(["22222222-2222-4222-8222-222222222222"]))
      expect(card[:presented_current_value]["items"].map { |i| i["fields"]["name"] }).to eq([ "n-2222" ])
    end

    context "the gate (a presenter spy, so the negative arms can fail)" do
      let(:calls) { [] }

      before do
        spy = calls
        register { |value, viewer| spy << viewer && { items: JSON.parse(value).map { |id| entry(id) }, omitted: 0 } }
      end

      it "runs the presenter for an admin.access holder (the positive arm the negatives depend on)" do
        card = card_for(admin)

        expect(calls).to eq([ admin ])
        expect(card).to have_key(:presented_new_value)
      end

      it "never calls the presenter for a viewer without admin.access, nil included" do
        [ reader, settings_manager, nil ].each { |viewer| card_for(viewer) }

        expect(calls).to be_empty
      end

      it "gives a settings.manage holder without admin.access the current value but no presentation" do
        SiteSetting.set(key, %(["#{id_a}"]), setting_type: "json")

        card = card_for(settings_manager)

        expect(card).to include(new_value: raw, current_value: %(["#{id_a}"]))
        expect(card).not_to have_key(:presented_new_value)
        expect(card).not_to have_key(:presented_current_value)
        expect(calls).to be_empty
      end
    end

    it "falls back to the raw value when the presenter raises" do
      register { |_| raise "boom" }

      card = card_for(admin)

      expect(card).to include(new_value: raw)
      expect(card).not_to have_key(:presented_new_value)
    end

    it "presents nothing for the current value when the setting is unset" do
      register { |value, _| { items: JSON.parse(value).map { |id| entry(id) }, omitted: 0 } }

      card = card_for(admin)

      expect(card[:current_value_set]).to be(false)
      expect(card).not_to have_key(:presented_current_value)
    end
  end

  describe "who receives it over REST", type: :request do
    let!(:approval) do
      SiteSetting.register_value_presenter(key) do |value, _|
        { items: JSON.parse(value).map { |id| { raw: id, fields: { name: "named" }, flags: [] } }, omitted: 0 }
      end
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

      it "#{list_path ? 'the queue' : 'the detail'} shows the presented value to an admin.access holder and to no one else" do
        expect(approval).to be_pending

        with = card_via(path_for.call(approval), admin)

        expect(with).to include("new_value" => raw)
        expect(with["presented_new_value"]["items"]).to eq([ { "raw" => id_a, "fields" => { "name" => "named" }, "flags" => [] } ])
        [ reader, settings_manager ].each do |viewer|
          without = card_via(path_for.call(approval), viewer)
          expect(without).to include("new_value" => raw)
          expect(without).not_to have_key("presented_new_value")
          expect(without).not_to have_key("presented_current_value")
        end
      end
    end
  end
end
