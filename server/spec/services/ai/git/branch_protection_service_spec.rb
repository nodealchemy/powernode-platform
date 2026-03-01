# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Git::BranchProtectionService, type: :service do
  let(:account) { create(:account) }
  let(:guardrail_config) do
    create(:ai_guardrail_config,
           account: account,
           ai_agent_id: nil,
           is_active: true,
           branch_protection_enabled: true,
           protected_branches: ["main", "master", "release/*"],
           require_worktree_for_repos: true,
           merge_approval_required: true)
  end

  subject(:service) { described_class.new(account: account) }

  # ===========================================================================
  # validate_commit_target!
  # ===========================================================================

  describe "#validate_commit_target!" do
    context "when protection is enabled" do
      before { guardrail_config }

      it "raises ProtectedBranchViolation for protected branch" do
        expect {
          service.validate_commit_target!("main")
        }.to raise_error(described_class::ProtectedBranchViolation, /main/)
      end

      it "raises for master branch" do
        expect {
          service.validate_commit_target!("master")
        }.to raise_error(described_class::ProtectedBranchViolation)
      end

      it "raises for glob-matched branches like release/*" do
        expect {
          service.validate_commit_target!("release/1.0")
        }.to raise_error(described_class::ProtectedBranchViolation)
      end

      it "allows commits to unprotected branches" do
        expect {
          service.validate_commit_target!("feature/my-feature")
        }.not_to raise_error
      end

      it "allows commits to develop branch" do
        expect {
          service.validate_commit_target!("develop")
        }.not_to raise_error
      end
    end

    context "when protection is disabled" do
      before do
        create(:ai_guardrail_config,
               account: account,
               ai_agent_id: nil,
               is_active: true,
               branch_protection_enabled: false)
      end

      it "allows commits to any branch" do
        expect {
          service.validate_commit_target!("main")
        }.not_to raise_error
      end
    end

    context "when no guardrail config exists" do
      it "allows commits to any branch" do
        expect {
          service.validate_commit_target!("main")
        }.not_to raise_error
      end
    end
  end

  # ===========================================================================
  # validate_merge_target
  # ===========================================================================

  describe "#validate_merge_target" do
    context "when protection and merge approval are enabled" do
      before { guardrail_config }

      it "requires approval for protected branch" do
        result = service.validate_merge_target("main")

        expect(result[:allowed]).to be false
        expect(result[:requires_approval]).to be true
        expect(result[:message]).to include("main")
      end

      it "allows merge to unprotected branch" do
        result = service.validate_merge_target("feature/branch")

        expect(result[:allowed]).to be true
        expect(result[:requires_approval]).to be false
      end
    end

    context "when protection is disabled" do
      it "allows merge to any branch" do
        result = service.validate_merge_target("main")

        expect(result[:allowed]).to be true
        expect(result[:requires_approval]).to be false
      end
    end
  end

  # ===========================================================================
  # validate_worktree_usage!
  # ===========================================================================

  describe "#validate_worktree_usage!" do
    context "when worktree is required" do
      before { guardrail_config }

      it "raises when working in main repository" do
        expect {
          service.validate_worktree_usage!(
            repository_path: "/repo",
            working_dir: "/repo"
          )
        }.to raise_error(described_class::WorktreeRequiredViolation)
      end

      it "allows working in a worktree directory" do
        expect {
          service.validate_worktree_usage!(
            repository_path: "/repo",
            working_dir: "/repo/.worktrees/feature-branch"
          )
        }.not_to raise_error
      end
    end

    context "when worktree is not required" do
      before do
        create(:ai_guardrail_config,
               account: account,
               ai_agent_id: nil,
               is_active: true,
               branch_protection_enabled: true,
               require_worktree_for_repos: false)
      end

      it "allows working in main repository" do
        expect {
          service.validate_worktree_usage!(
            repository_path: "/repo",
            working_dir: "/repo"
          )
        }.not_to raise_error
      end
    end
  end

  # ===========================================================================
  # protection_summary
  # ===========================================================================

  describe "#protection_summary" do
    context "with active protection" do
      before { guardrail_config }

      it "returns full protection summary" do
        summary = service.protection_summary

        expect(summary[:enabled]).to be true
        expect(summary[:protected_branches]).to include("main", "master")
        expect(summary[:require_worktree]).to be true
        expect(summary[:merge_approval_required]).to be true
      end
    end

    context "without guardrail config" do
      it "returns disabled summary" do
        summary = service.protection_summary

        expect(summary[:enabled]).to be false
      end
    end
  end

  # ===========================================================================
  # branch_protected?
  # ===========================================================================

  describe "#branch_protected?" do
    before { guardrail_config }

    it "returns true for protected branches" do
      expect(service.branch_protected?("main")).to be true
      expect(service.branch_protected?("master")).to be true
      expect(service.branch_protected?("release/2.0")).to be true
    end

    it "returns false for unprotected branches" do
      expect(service.branch_protected?("feature/new")).to be false
      expect(service.branch_protected?("develop")).to be false
    end
  end
end
