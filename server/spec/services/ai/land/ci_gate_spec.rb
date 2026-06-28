# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Land::CiGate do
  let(:account) { create(:account) }
  let(:repository) { create(:devops_repository, account: account) }

  def pipeline(sha:, status:, conclusion: nil, repo: repository)
    Devops::GitPipeline.create!(
      account: account, repository: repo, external_id: SecureRandom.hex(8),
      name: "ci", sha: sha, status: status, conclusion: conclusion
    )
  end

  describe ".status_for" do
    it "returns :missing for a blank sha or no pipeline" do
      expect(described_class.status_for(sha: nil, repository: repository)).to eq(:missing)
      expect(described_class.status_for(sha: "deadbeef", repository: repository)).to eq(:missing)
    end

    it "returns :success when a finished pipeline concluded success" do
      pipeline(sha: "abc123", status: "completed", conclusion: "success")
      expect(described_class.status_for(sha: "abc123", repository: repository)).to eq(:success)
    end

    it "returns :failure when a finished pipeline concluded non-success" do
      pipeline(sha: "bad123", status: "failed", conclusion: "failure")
      expect(described_class.status_for(sha: "bad123", repository: repository)).to eq(:failure)
    end

    it "returns :pending when a pipeline for the sha is still running" do
      pipeline(sha: "run123", status: "in_progress")
      expect(described_class.status_for(sha: "run123", repository: repository)).to eq(:pending)
    end

    it "prefers the latest finished pipeline" do
      pipeline(sha: "x", status: "failed", conclusion: "failure").update!(created_at: 1.hour.ago)
      pipeline(sha: "x", status: "completed", conclusion: "success")
      expect(described_class.status_for(sha: "x", repository: repository)).to eq(:success)
    end

    it "scopes to the given repository" do
      other = create(:devops_repository, account: account)
      pipeline(sha: "shared", status: "completed", conclusion: "success", repo: other)
      expect(described_class.status_for(sha: "shared", repository: repository)).to eq(:missing)
    end
  end
end
