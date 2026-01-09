# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::PipelineApproval, type: :model do
  subject(:approval) { build(:git_pipeline_approval) }

  describe 'associations' do
    it { is_expected.to belong_to(:pipeline) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:requested_by).class_name('User').optional }
    it { is_expected.to belong_to(:responded_by).class_name('User').optional }
    it { is_expected.to have_one(:repository).through(:pipeline) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:gate_name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_length_of(:gate_name).is_at_most(100) }

    it 'validates status inclusion' do
      Git::PipelineApproval::STATUSES.each do |status|
        approval = build(:git_pipeline_approval, status: status)
        expect(approval).to be_valid
      end
    end

    it 'validates gate_name uniqueness scoped to pipeline' do
      existing = create(:git_pipeline_approval)
      duplicate = build(:git_pipeline_approval,
                        pipeline: existing.pipeline,
                        gate_name: existing.gate_name)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:gate_name]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, repository: repo, account: account) }

    let!(:pending_approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }
    let!(:approved_approval) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }
    let!(:rejected_approval) { create(:git_pipeline_approval, :rejected, pipeline: pipeline, account: account) }
    let!(:expired_approval) { create(:git_pipeline_approval, :expired, pipeline: pipeline, account: account) }
    let!(:cancelled_approval) { create(:git_pipeline_approval, :cancelled, pipeline: pipeline, account: account) }

    describe '.pending' do
      it 'returns only pending approvals' do
        expect(described_class.pending).to include(pending_approval)
        expect(described_class.pending).not_to include(approved_approval, rejected_approval)
      end
    end

    describe '.approved' do
      it 'returns only approved approvals' do
        expect(described_class.approved).to include(approved_approval)
        expect(described_class.approved).not_to include(pending_approval, rejected_approval)
      end
    end

    describe '.rejected' do
      it 'returns only rejected approvals' do
        expect(described_class.rejected).to include(rejected_approval)
        expect(described_class.rejected).not_to include(pending_approval, approved_approval)
      end
    end

    describe '.expired' do
      it 'returns only expired approvals' do
        expect(described_class.expired).to include(expired_approval)
        expect(described_class.expired).not_to include(pending_approval)
      end
    end

    describe '.cancelled' do
      it 'returns only cancelled approvals' do
        expect(described_class.cancelled).to include(cancelled_approval)
        expect(described_class.cancelled).not_to include(pending_approval)
      end
    end

    describe '.active' do
      let!(:active_approval) { create(:git_pipeline_approval, status: 'pending', expires_at: 1.hour.from_now, pipeline: pipeline, account: account) }
      let!(:expired_pending) { create(:git_pipeline_approval, status: 'pending', expires_at: 1.hour.ago, pipeline: pipeline, account: account) }

      it 'returns pending approvals not yet expired' do
        expect(described_class.active).to include(active_approval)
        expect(described_class.active).not_to include(expired_pending)
      end
    end

    describe '.expiring_soon' do
      let!(:expiring_approval) { create(:git_pipeline_approval, :expiring_soon, pipeline: pipeline, account: account) }

      it 'returns pending approvals expiring within 1 hour' do
        expect(described_class.expiring_soon).to include(expiring_approval)
        expect(described_class.expiring_soon).not_to include(pending_approval)
      end
    end

    describe '.for_pipeline' do
      it 'filters by pipeline' do
        result = described_class.for_pipeline(pipeline.id)
        expect(result).to include(pending_approval)
      end
    end

    describe '.for_environment' do
      let!(:prod_approval) { create(:git_pipeline_approval, :production, pipeline: pipeline, account: account) }
      let!(:staging_approval) { create(:git_pipeline_approval, :staging, pipeline: pipeline, account: account) }

      it 'filters by environment' do
        expect(described_class.for_environment('production')).to include(prod_approval)
        expect(described_class.for_environment('staging')).to include(staging_approval)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        result = described_class.recent
        expect(result.first.created_at).to be >= result.last.created_at
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create :set_default_expiry' do
      it 'sets expires_at to 24 hours from now if not set' do
        approval = build(:git_pipeline_approval, expires_at: nil)
        approval.save!
        expect(approval.expires_at).to be_within(1.minute).of(24.hours.from_now)
      end

      it 'does not override provided expires_at' do
        custom_expiry = 48.hours.from_now
        approval = build(:git_pipeline_approval, expires_at: custom_expiry)
        approval.save!
        expect(approval.expires_at).to be_within(1.second).of(custom_expiry)
      end
    end
  end

  describe 'instance methods' do
    describe 'status query methods' do
      it '#pending? returns true for pending status' do
        expect(build(:git_pipeline_approval, :pending).pending?).to be true
        expect(build(:git_pipeline_approval, :approved).pending?).to be false
      end

      it '#approved? returns true for approved status' do
        expect(build(:git_pipeline_approval, :approved).approved?).to be true
        expect(build(:git_pipeline_approval, :pending).approved?).to be false
      end

      it '#rejected? returns true for rejected status' do
        expect(build(:git_pipeline_approval, :rejected).rejected?).to be true
        expect(build(:git_pipeline_approval, :pending).rejected?).to be false
      end

      it '#expired? returns true for expired status' do
        expect(build(:git_pipeline_approval, :expired).expired?).to be true
        expect(build(:git_pipeline_approval, :pending).expired?).to be false
      end

      it '#cancelled? returns true for cancelled status' do
        expect(build(:git_pipeline_approval, :cancelled).cancelled?).to be true
        expect(build(:git_pipeline_approval, :pending).cancelled?).to be false
      end
    end

    describe '#can_respond?' do
      it 'returns true for pending approval not past expiry' do
        approval = build(:git_pipeline_approval, :pending, expires_at: 1.hour.from_now)
        expect(approval.can_respond?).to be true
      end

      it 'returns false for non-pending approval' do
        approval = build(:git_pipeline_approval, :approved)
        expect(approval.can_respond?).to be false
      end

      it 'returns false for expired pending approval' do
        approval = build(:git_pipeline_approval, :pending, expires_at: 1.hour.ago)
        expect(approval.can_respond?).to be false
      end
    end

    describe '#past_expiry?' do
      it 'returns true when expires_at is in the past' do
        approval = build(:git_pipeline_approval, expires_at: 1.hour.ago)
        expect(approval.past_expiry?).to be true
      end

      it 'returns false when expires_at is in the future' do
        approval = build(:git_pipeline_approval, expires_at: 1.hour.from_now)
        expect(approval.past_expiry?).to be false
      end

      it 'returns false when expires_at is nil' do
        approval = build(:git_pipeline_approval, expires_at: nil)
        expect(approval.past_expiry?).to be false
      end
    end

    describe '#time_until_expiry' do
      it 'returns seconds until expiry' do
        approval = build(:git_pipeline_approval, expires_at: 1.hour.from_now)
        expect(approval.time_until_expiry).to be_within(60).of(3600)
      end

      it 'returns 0 when past expiry' do
        approval = build(:git_pipeline_approval, expires_at: 1.hour.ago)
        expect(approval.time_until_expiry).to eq(0)
      end

      it 'returns nil when expires_at is nil' do
        approval = build(:git_pipeline_approval, expires_at: nil)
        expect(approval.time_until_expiry).to be_nil
      end
    end

    describe '#response_time' do
      it 'returns time between creation and response' do
        approval = build(:git_pipeline_approval,
                         created_at: 1.hour.ago,
                         responded_at: Time.current)
        expect(approval.response_time).to be_within(60).of(3600)
      end

      it 'returns nil when not responded' do
        approval = build(:git_pipeline_approval, responded_at: nil)
        expect(approval.response_time).to be_nil
      end
    end
  end

  describe 'status transitions' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, repository: repo, account: account) }

    describe '#approve!' do
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, expires_at: 1.hour.from_now) }

      it 'transitions to approved status' do
        approval.approve!(user, 'Looks good')
        expect(approval.status).to eq('approved')
        expect(approval.responded_by).to eq(user)
        expect(approval.response_comment).to eq('Looks good')
        expect(approval.responded_at).to be_within(1.second).of(Time.current)
      end

      it 'returns false if cannot respond' do
        expired_approval = create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, expires_at: 1.hour.ago)
        expect(expired_approval.approve!(user)).to be false
      end
    end

    describe '#reject!' do
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, expires_at: 1.hour.from_now) }

      it 'transitions to rejected status' do
        approval.reject!(user, 'Tests failing')
        expect(approval.status).to eq('rejected')
        expect(approval.responded_by).to eq(user)
        expect(approval.response_comment).to eq('Tests failing')
        expect(approval.responded_at).to be_within(1.second).of(Time.current)
      end

      it 'returns false if cannot respond' do
        already_approved = create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account)
        expect(already_approved.reject!(user)).to be false
      end
    end

    describe '#expire!' do
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }

      it 'transitions to expired status' do
        approval.expire!
        expect(approval.status).to eq('expired')
        expect(approval.responded_at).to be_within(1.second).of(Time.current)
      end

      it 'returns false if not pending' do
        approved = create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account)
        expect(approved.expire!).to be false
      end
    end

    describe '#cancel!' do
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }

      it 'transitions to cancelled status' do
        approval.cancel!
        expect(approval.status).to eq('cancelled')
        expect(approval.responded_at).to be_within(1.second).of(Time.current)
      end

      it 'returns false if not pending' do
        approved = create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account)
        expect(approved.cancel!).to be false
      end
    end
  end

  describe '#can_user_approve?' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, repository: repo, account: account) }

    context 'when no required_approvers' do
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, required_approvers: []) }

      it 'returns true for any user' do
        expect(approval.can_user_approve?(user)).to be true
      end
    end

    context 'when user is in required_approvers' do
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, required_approvers: [user.id]) }

      it 'returns true' do
        expect(approval.can_user_approve?(user)).to be true
      end
    end

    context 'when user is not in required_approvers' do
      let(:other_user) { create(:user, account: account) }
      let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, required_approvers: [other_user.id]) }

      it 'returns false' do
        expect(approval.can_user_approve?(user)).to be false
      end
    end

    context 'when approval is not pending' do
      let(:approval) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }

      it 'returns false' do
        expect(approval.can_user_approve?(user)).to be false
      end
    end
  end

  describe 'class methods' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, repository: repo, account: account) }

    describe '.expire_stale!' do
      let!(:stale_approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, expires_at: 1.hour.ago) }
      let!(:fresh_approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account, expires_at: 1.hour.from_now) }

      it 'expires pending approvals past their expiry' do
        described_class.expire_stale!
        expect(stale_approval.reload.status).to eq('expired')
        expect(fresh_approval.reload.status).to eq('pending')
      end
    end

    describe '.stats_for_account' do
      before do
        create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account)
        create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account)
        create(:git_pipeline_approval, :rejected, pipeline: pipeline, account: account)
        create(:git_pipeline_approval, :expired, pipeline: pipeline, account: account)
      end

      it 'returns approval statistics' do
        stats = described_class.stats_for_account(account.id)
        expect(stats[:total]).to eq(4)
        expect(stats[:pending]).to eq(1)
        expect(stats[:approved]).to eq(1)
        expect(stats[:rejected]).to eq(1)
        expect(stats[:expired]).to eq(1)
      end
    end
  end

  describe 'validation: response_requires_responder' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, repository: repo, account: account) }
    let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }

    it 'requires responded_by when approving' do
      approval.status = 'approved'
      approval.responded_by = nil
      expect(approval).not_to be_valid
      expect(approval.errors[:responded_by]).to include('is required when approving or rejecting')
    end

    it 'requires responded_by when rejecting' do
      approval.status = 'rejected'
      approval.responded_by = nil
      expect(approval).not_to be_valid
      expect(approval.errors[:responded_by]).to include('is required when approving or rejecting')
    end
  end
end
