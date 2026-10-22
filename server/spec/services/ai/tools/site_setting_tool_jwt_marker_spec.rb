# frozen_string_literal: true

require "rails_helper"

# The documented HS256 revert, end to end through the door it names: with the
# stored secrets deleted, a person clears jwt_hmac_rotated_at to "" through
# site_setting_set_protected, approves it in their own session, and the key
# store then reads "not rotated" (so JWT_SECRET_KEY is trusted again).
RSpec.describe Ai::Tools::SiteSettingTool, "clearing the JWT rotation marker" do
  let(:account) { create(:account) }
  let!(:requester) { create(:user, account: account, permissions: [ "admin.access" ]) }
  let(:confirmer) { create(:user, account: account, permissions: [ "admin.access", "ai.autonomy.approve" ]) }
  let(:marker) { Security::JwtKeyStore::ROTATION_MARKER }

  after do
    ::Mcp::Principal.reset!
    Security::JwtKeyStore.clear_cache!
  end

  it "clears the marker on a person's own-session approval, and the store reads not rotated" do
    Security::JwtKeyStore.rotate_hmac!(grace_hours: 24)
    [ Security::JwtKeyStore::ACTIVE_HMAC_SECRET, Security::JwtKeyStore::HMAC_KEYRING ].each do |key|
      Security::SecretStore.delete(account: nil, scope: Security::JwtKeyStore::SCOPE, key: key)
    end

    tool = described_class.new(account: account, user: requester)
    tool.call_origin = "mcp_oauth"
    result = tool.execute(params: { action: "site_setting_set_protected", key: marker, value: "" })
    expect(result).to include(success: true)
    operation = Ai::DeferredOperation.find(result[:data][:deferred_operation_id])

    approved = Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                                    .approve(request: operation.approval_request, approver: confirmer,
                                                             origin: Ai::ApprovalDecision::REST_SESSION)

    expect(approved).to be(true)
    expect(SiteSetting.get(marker)).to eq("")
    Security::JwtKeyStore.clear_cache!
    expect(Security::JwtKeyStore.send(:rotation_recorded?)).to be(false)
  end

  # The tool parks the request; the value check runs when the approved write
  # lands, and its authored reason must come back as the operation's outcome,
  # not as an exception out of the approval.
  it "refuses to clear the marker while the rotated secret is still stored, as a result, not a raise" do
    Security::JwtKeyStore.rotate_hmac!(grace_hours: 24)

    tool = described_class.new(account: account, user: requester)
    tool.call_origin = "mcp_oauth"
    result = tool.execute(params: { action: "site_setting_set_protected", key: marker, value: "" })
    operation = Ai::DeferredOperation.find(result.dig(:data, :deferred_operation_id))

    expect {
      Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                           .approve(request: operation.approval_request, approver: confirmer,
                                                    origin: Ai::ApprovalDecision::REST_SESSION)
    }.not_to raise_error

    operation.reload
    outcome = [ operation.error_message, operation.result.to_json ].join(" ")
    expect(outcome).to include("the store still holds a rotated HS256 secret; delete it first")
    expect(SiteSetting.get(marker)).to be_present
  end
end
