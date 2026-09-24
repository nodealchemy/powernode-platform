# frozen_string_literal: true

require "rails_helper"

# fc-12 review: the governance approval read surface was deleted, and with it
# approval_serializer_parity_spec.rb — a parity guard between two independently
# maintained serializers. With only one serializer left there is nothing left
# to drift apart from, but the byte-identity regression pins that spec also
# carried for the AUTONOMY surface (the one that survives) went with it. This
# file restores those pins on their own, autonomy-only terms: no parity, no
# DIVERGENT_KEYS exception list, just "these are the keys this payload has."
#
# The oracle is still DERIVED, not hand-listed, for the fields
# Ai::ApprovalRequestSerialization::CORE_KEYS defines (execution_status,
# execution_error, requires_human_session, and so on) — a field added there is
# covered here without editing this spec. The autonomy-only additions
# (agent_*/action_* denormalisations, requested_by_id, total_steps,
# current_step_can_approve, and the detail-only approval_chain / step_statuses
# / decisions / deferred_operation) are hand-listed, because they are this
# surface's own and nothing derives them.
RSpec.describe "Autonomy approvals — serialized key set", type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:headers) { auth_headers_for(reader) }

  let!(:approval_request) { create(:ai_approval_request, account: account, status: "pending") }

  # This surface's own additions on top of the shared core — present on both
  # the list row and the detail payload.
  let(:autonomy_additions) do
    %w[agent_id agent_name action_type action_category requested_by_id total_steps current_step_can_approve]
  end

  # Present on the detail payload only.
  let(:detail_only_additions) { %w[approval_chain step_statuses decisions deferred_operation] }

  def detail_payload
    get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)["data"]
  end

  def list_row
    get "/api/v1/ai/autonomy/approvals", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    rows = JSON.parse(response.body)["data"]
    expect(rows).to be_present, "no rows to pin — the fixture stopped being listed"
    rows.find { |row| row["id"] == approval_request.id }
  end

  describe "the shared core" do
    it "is defined in exactly one place" do
      expect(defined?(::Ai::ApprovalRequestSerialization::CORE_KEYS)).to eq("constant"),
        "the autonomy surface no longer builds its core payload from " \
        "Ai::ApprovalRequestSerialization::CORE_KEYS — there is no single " \
        "definition for this spec to derive its oracle from."

      expect(::Ai::ApprovalRequestSerialization::CORE_KEYS).to include(
        :execution_status, :execution_error, :requires_human_session, :request_data
      )
    end

    it "is emitted on both the list row and the detail payload" do
      list = list_row
      detail = detail_payload

      ::Ai::ApprovalRequestSerialization::CORE_KEYS.each do |key|
        k = key.to_s
        expect(list).to have_key(k), "list row is missing core key #{k}"
        expect(detail).to have_key(k), "detail payload is missing core key #{k}"
      end
    end
  end

  describe "response shape" do
    it "pins the detail key set" do
      expected = (::Ai::ApprovalRequestSerialization::CORE_KEYS.map(&:to_s) +
                  autonomy_additions + detail_only_additions).sort

      expect(detail_payload.keys.sort).to eq(expected)
    end

    it "pins the list row key set (no detail-only fields)" do
      expected = (::Ai::ApprovalRequestSerialization::CORE_KEYS.map(&:to_s) + autonomy_additions).sort

      expect(list_row.keys.sort).to eq(expected)
      detail_only_additions.each do |key|
        expect(list_row).not_to have_key(key)
      end
    end
  end
end
