# frozen_string_literal: true

require "rails_helper"

# IMP-1765f6f09458 — the change card's digest binds an approval to exactly what
# the card showed: the key, the new value and the current value AT RENDER. It is
# computed server-side on render and recomputed at decide time; the client only
# echoes it. Deterministic, and absent from a card that does not carry the
# current value (a digest over a withheld boolean would be a two-guess oracle).
RSpec.describe Ai::Approvals::ChangeCard, "the digest" do
  let(:account) { create(:account) }
  let(:operator) { create(:user, account: account, permissions: [ "admin.access" ]) }
  let(:reader) { create(:user, account: account, permissions: [ "ai.agents.read" ]) }
  let(:key) { "zz_change_card_digest_key" }

  let!(:request) do
    create(:ai_approval_request, account: account, status: "pending",
                                 request_data: { "executor_class" => "Ai::Executors::DeferredToolCall", "params" => {
                                   "tool_class" => "Ai::Tools::SiteSettingTool",
                                   "action" => "site_setting_set_protected",
                                   "tool_params" => { "key" => key, "value" => "new-value" }
                                 } })
  end

  before do
    Ai::Tools::SiteSettingTool.register_key(key, setting_type: "string", description: "digest spec", protected: true)
    SiteSetting.set(key, "old-value")
  end

  def card(viewer = operator) = described_class.for(request, viewer: viewer)

  it "is a versioned sha256, the same for two renders of an unchanged setting" do
    first_render = card
    second_render = card

    expect(first_render[:digest]).to match(/\Av1:[0-9a-f]{64}\z/)
    expect(second_render[:digest]).to eq(first_render[:digest])
  end

  it "is the digest of exactly (tool, action, key, new value, current value set, current value)" do
    canonical = JSON.generate([ "v1", "site_setting", "site_setting_set_protected", key, "new-value", true, "old-value" ])

    expect(card[:digest]).to eq("v1:#{Digest::SHA256.hexdigest(canonical)}")
    expect(described_class.digest(card)).to eq(card[:digest])
  end

  it "changes when the current value changes, and when the setting is unset" do
    before = card[:digest]
    SiteSetting.set(key, "changed")
    changed = card[:digest]
    SiteSetting.where(key: key).delete_all
    unset = card[:digest]

    expect([ before, changed, unset ].uniq.size).to eq(3)
    expect(card).to include(current_value_set: false)
  end

  it "changes when the new value differs" do
    other = create(:ai_approval_request, account: account, status: "pending",
                                         request_data: request.request_data.deep_merge(
                                           "params" => { "tool_params" => { "value" => "other-value" } }
                                         ))

    expect(described_class.for(other, viewer: operator)[:digest]).not_to eq(card[:digest])
  end

  it "is absent from a card whose viewer is not shown the current value" do
    withheld = card(reader)

    expect(withheld).to include(key: key, new_value: "new-value")
    expect(withheld).not_to have_key(:current_value)
    expect(withheld).not_to have_key(:digest)
  end

  it "does not carry the presenter's rendering: a presenter change alone does not stale a decision" do
    SiteSetting.register_value_presenter(key) { |value, _viewer| { items: [ { raw: value.to_s } ], omitted: 0 } }
    presented = card
    expect(presented[:presented_new_value]).to be_present

    expect(presented[:digest]).to eq(described_class.digest(presented.except(:presented_new_value, :presented_current_value)))
  ensure
    SiteSetting.value_presenters.delete(key)
  end

  it "verifies constant-time and treats a non-string as a mismatch" do
    expect(described_class.digest_matches?(card, card[:digest])).to be(true)
    expect(described_class.digest_matches?(card, card[:digest].succ)).to be(false)
    expect(described_class.digest_matches?(card, [ card[:digest] ])).to be(false)
    expect(described_class.digest_matches?(card, nil)).to be(false)
    expect(described_class.digest_matches?(card(reader), "v1:#{'0' * 64}")).to be(false)
  end
end
