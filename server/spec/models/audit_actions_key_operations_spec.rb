# frozen_string_literal: true

require "rails_helper"

# The account teardown re-homes only EXPLICITLY listed key-operation audit actions
# (no pattern guessing). Extensions register theirs the way they register actions.
RSpec.describe AuditActions, ".key_operation?" do
  it "is true for listed core key operations" do
    %w[api_key_created api_key_revoked api_key_regenerated ai.providers.credential.rotate
       ai_provider_credential_deleted ai.data_sources.credential.create].each do |a|
      expect(described_class.key_operation?(a)).to be(true), a
    end
  end

  it "is false for look-alikes and unrelated actions" do
    %w[user_created api_key_status_changed monkey_created secret_santa_created credential_viewed foo_key_created].each do |a|
      expect(described_class.key_operation?(a)).to be(false), a
    end
  end

  it "lists only actions that are valid audit actions" do
    expect(described_class::CORE_KEY_OPERATION_ACTIONS - described_class::CORE_ALL_ACTIONS).to be_empty
  end

  it "includes actions an extension registers, and forgets them when re-registered" do
    described_class.register_key_operation_actions("probe", %w[probe.key.rotated])
    expect(described_class.key_operation?("probe.key.rotated")).to be true
    described_class.register_key_operation_actions("probe", [])
    expect(described_class.key_operation?("probe.key.rotated")).to be false
  end
end
