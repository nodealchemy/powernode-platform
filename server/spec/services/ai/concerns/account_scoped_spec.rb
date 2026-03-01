# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Concerns::AccountScoped do
  let(:test_class) do
    Class.new do
      include Ai::Concerns::AccountScoped
    end
  end

  let(:account) { create(:account) }
  let(:instance) { test_class.new(account: account) }

  describe "#initialize" do
    it "sets the account" do
      expect(instance.account).to eq(account)
    end
  end

  describe "#success_response" do
    it "returns success with data" do
      result = instance.send(:success_response, { items: [1, 2] }, message: "Done")
      expect(result).to eq({ success: true, message: "Done", items: [1, 2] })
    end

    it "returns success without message" do
      result = instance.send(:success_response, { count: 5 })
      expect(result).to eq({ success: true, count: 5 })
    end
  end

  describe "#error_response" do
    it "returns error with message" do
      result = instance.send(:error_response, "Not found", code: :not_found)
      expect(result).to eq({ success: false, error: "Not found", code: :not_found })
    end

    it "returns error with details" do
      result = instance.send(:error_response, "Invalid", details: { field: "name" })
      expect(result).to eq({ success: false, error: "Invalid", details: { field: "name" } })
    end
  end

  describe "#audit_action" do
    it "creates a compliance audit entry" do
      expect {
        instance.send(:audit_action,
          action: "test_action",
          resource_type: "Ai::Agent",
          resource_id: "test-id",
          details: { description: "Test", outcome: "success" }
        )
      }.to change(Ai::ComplianceAuditEntry, :count).by(1)
    end

    it "does not raise on failure" do
      allow(Ai::ComplianceAuditEntry).to receive(:create).and_raise(StandardError, "DB error")
      expect {
        instance.send(:audit_action, action: "test")
      }.not_to raise_error
    end
  end
end
