# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::PipelineManagementTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("pipeline_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :pipeline_id, :repository_id, :branch)
    end

    it "marks action as required" do
      expect(described_class.definition[:parameters][:action][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires git.pipelines.manage permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("git.pipelines.manage")
    end
  end

  describe "#execute" do
    context "with trigger_pipeline action" do
      it "triggers a pipeline for a valid repository" do
        repository = create(:git_repository, account: account)
        result = tool.execute(params: { action: "trigger_pipeline", repository_id: repository.id })
        expect(result[:success]).to be true
        expect(result[:status]).to eq("triggered")
      end

      it "returns error for non-existent repository" do
        result = tool.execute(params: { action: "trigger_pipeline", repository_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "with list_pipelines action" do
      it "returns pipelines for the account" do
        result = tool.execute(params: { action: "list_pipelines" })
        expect(result[:success]).to be true
        expect(result).to have_key(:count)
      end
    end

    context "with get_pipeline_status action" do
      it "returns error for non-existent pipeline" do
        result = tool.execute(params: { action: "get_pipeline_status", pipeline_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "self_destruct" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when action is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: action/)
      end
    end
  end
end
