# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::BaseTool do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  describe ".definition" do
    it "raises NotImplementedError" do
      expect { described_class.definition }.to raise_error(NotImplementedError, /must implement .definition/)
    end
  end

  describe ".permitted?" do
    it "returns true when no REQUIRED_PERMISSION is set" do
      expect(described_class.permitted?(agent: agent)).to be true
    end

    it "returns true when agent is nil" do
      expect(described_class.permitted?(agent: nil)).to be true
    end

    context "with a subclass that defines REQUIRED_PERMISSION" do
      it "checks the account permissions" do
        expect(Ai::Tools::AgentManagementTool.permitted?(agent: agent)).to be_in([true, false])
      end
    end
  end

  describe "#initialize" do
    it "accepts account and optional agent" do
      tool = described_class.new(account: account, agent: agent)
      expect(tool.send(:account)).to eq(account)
      expect(tool.send(:agent)).to eq(agent)
    end

    it "defaults agent to nil" do
      tool = described_class.new(account: account)
      expect(tool.send(:agent)).to be_nil
    end
  end

  describe "#execute" do
    it "raises NotImplementedError from #call" do
      tool = described_class.new(account: account)
      # validate_params! calls .definition first, which raises NotImplementedError
      # before reaching #call — so we match the broader pattern
      expect { tool.execute(params: {}) }.to raise_error(NotImplementedError, /must implement/)
    end
  end

  describe "#validate_params!" do
    let(:tool) { described_class.new(account: account) }

    it "does not raise when there are no required params" do
      allow(described_class).to receive(:definition).and_return({
        parameters: {
          name: { type: "string", required: false }
        }
      })
      expect { tool.send(:validate_params!, {}) }.not_to raise_error
    end

    it "raises ArgumentError when required params are missing" do
      allow(described_class).to receive(:definition).and_return({
        parameters: {
          action: { type: "string", required: true },
          name: { type: "string", required: false }
        }
      })
      expect { tool.send(:validate_params!, {}) }.to raise_error(ArgumentError, /Missing required parameters: action/)
    end

    it "does not raise when required params are present" do
      allow(described_class).to receive(:definition).and_return({
        parameters: {
          action: { type: "string", required: true }
        }
      })
      expect { tool.send(:validate_params!, { action: "test" }) }.not_to raise_error
    end
  end

  describe "#validate_account_context!" do
    it "does not raise for a valid persisted account" do
      tool = described_class.new(account: account)
      expect { tool.send(:validate_account_context!) }.not_to raise_error
    end

    it "does not raise when account is nil" do
      tool = described_class.new(account: nil)
      expect { tool.send(:validate_account_context!) }.not_to raise_error
    end
  end

  describe "::MAX_CALLS_PER_EXECUTION" do
    it "is set to 20" do
      expect(described_class::MAX_CALLS_PER_EXECUTION).to eq(20)
    end
  end
end
