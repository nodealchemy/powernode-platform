# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Land::LandService do
  let(:account) { create(:account) }
  let(:campaign) { create(:ai_campaign, account: account) }
  let(:wm) { instance_double(Ai::Git::WorktreeManager) }

  before { allow(Ai::Git::WorktreeManager).to receive(:new).and_return(wm) }

  def land(status:)
    Ai::CampaignLand.create!(
      campaign: campaign, account: account, status: status,
      source_branch: "campaign/#{campaign.id}", target_branch: "develop"
    )
  end

  describe "#stage!" do
    subject(:service) { described_class.new(land(status: "staging")) }

    it "pushes the source branch and advances to staged_ci" do
      allow(wm).to receive(:fetch_branch).and_return(success: true)
      allow(wm).to receive(:push_branch).and_return(success: true)
      allow(service).to receive(:rev_parse).with("origin/develop").and_return("basesha")
      allow(service).to receive(:rev_parse).with(/\Acampaign\//).and_return("stagedsha")

      service.stage!
      l = service.instance_variable_get(:@land).reload
      expect(l).to have_attributes(status: "staged_ci", base_sha: "basesha", staged_sha: "stagedsha")
    end

    it "parks when the push fails" do
      allow(wm).to receive(:fetch_branch).and_return(success: true)
      allow(service).to receive(:rev_parse).and_return("sha")
      allow(wm).to receive(:push_branch).and_return(success: false, error: "denied")

      service.stage!
      expect(service.instance_variable_get(:@land).reload.status).to eq("parked")
      expect(campaign.parked_questions.count).to eq(1)
    end
  end

  describe "#merge!" do
    subject(:service) { described_class.new(land(status: "staged_ci")) }
    let(:session) { instance_double(Ai::WorktreeSession) }
    let(:merge_svc) { instance_double(Ai::Git::MergeService) }

    before do
      allow(service).to receive(:build_merge_session).and_return(session)
      allow(Ai::Git::MergeService).to receive(:new).with(session: session).and_return(merge_svc)
      allow(wm).to receive(:push_branch).and_return(success: true)
    end

    it "advances to verifying on a completed merge" do
      op_id = "019f0000-0000-7000-8000-000000000001"
      op = instance_double(Ai::MergeOperation, status: "completed", merge_commit_sha: "mergedsha", id: op_id, conflict_files: [])
      allow(merge_svc).to receive(:execute).and_return(requires_approval: true)
      allow(merge_svc).to receive(:approve_merge!).and_return(success: true)
      allow(session).to receive(:merge_operations).and_return(double(order: double(last: op)))

      service.merge!
      expect(service.instance_variable_get(:@land).reload).to have_attributes(
        status: "verifying", merged_sha: "mergedsha", merge_operation_id: op_id
      )
    end

    it "parks on a merge conflict" do
      op = instance_double(Ai::MergeOperation, status: "conflict", conflict_files: ["a.rb"], merge_commit_sha: nil, id: "op-2")
      allow(merge_svc).to receive(:execute).and_return(success: true)
      allow(session).to receive(:merge_operations).and_return(double(order: double(last: op)))

      service.merge!
      l = service.instance_variable_get(:@land).reload
      expect(l).to have_attributes(status: "parked", conflict_files: ["a.rb"])
    end
  end

  describe "kill-switch" do
    it "parks instead of mutating the target when the account is suspended" do
      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)
      service = described_class.new(land(status: "staging"))
      expect(wm).not_to receive(:push_branch)

      service.stage!
      expect(service.instance_variable_get(:@land).reload.status).to eq("parked")
    end
  end
end
