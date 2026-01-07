# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CiCd::StepApprovalToken, type: :model do
  let(:account) { create(:account) }
  let(:pipeline) { create(:ci_cd_pipeline, account: account) }
  let(:pipeline_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline) }
  let(:pipeline_run) { create(:ci_cd_pipeline_run, :running, pipeline: pipeline) }
  let(:step_execution) do
    create(:ci_cd_step_execution,
           :waiting_approval,
           pipeline_run: pipeline_run,
           pipeline_step: pipeline_step)
  end

  describe 'associations' do
    it { is_expected.to belong_to(:step_execution).class_name('CiCd::StepExecution') }
    it { is_expected.to belong_to(:recipient_user).class_name('User').optional }
    it { is_expected.to belong_to(:responded_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:ci_cd_step_approval_token, step_execution: step_execution) }

    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_presence_of(:recipient_email) }
    # Note: expires_at is auto-set by before_validation callback, so we test the callback instead

    it 'auto-sets expires_at if not provided via callback' do
      token = build(:ci_cd_step_approval_token, step_execution: step_execution, expires_at: nil)
      token.valid?
      expect(token.expires_at).to be_present
    end

    it 'validates email format' do
      token = build(:ci_cd_step_approval_token,
                    step_execution: step_execution,
                    recipient_email: 'invalid-email')
      expect(token).not_to be_valid
      expect(token.errors[:recipient_email]).to be_present
    end

    it 'validates status inclusion' do
      valid_statuses = %w[pending approved rejected expired]
      valid_statuses.each do |status|
        token = build(:ci_cd_step_approval_token,
                      step_execution: step_execution,
                      status: status)
        token.token_digest = SecureRandom.hex(32)
        expect(token).to be_valid, "Expected status '#{status}' to be valid"
      end
    end

    it 'validates token_digest uniqueness' do
      existing_token = create(:ci_cd_step_approval_token, step_execution: step_execution)
      duplicate_token = build(:ci_cd_step_approval_token,
                              step_execution: step_execution,
                              token_digest: existing_token.token_digest)
      expect(duplicate_token).not_to be_valid
      expect(duplicate_token.errors[:token_digest]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:pending_token) do
      create(:ci_cd_step_approval_token,
             step_execution: step_execution,
             status: 'pending',
             expires_at: 1.day.from_now)
    end

    let(:other_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline, name: 'Other Step') }
    let(:other_execution) do
      create(:ci_cd_step_execution,
             :waiting_approval,
             pipeline_run: pipeline_run,
             pipeline_step: other_step)
    end
    let!(:approved_token) do
      create(:ci_cd_step_approval_token,
             step_execution: other_execution,
             status: 'approved',
             expires_at: 1.day.from_now)
    end

    let(:third_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline, name: 'Third Step') }
    let(:third_execution) do
      create(:ci_cd_step_execution,
             :waiting_approval,
             pipeline_run: pipeline_run,
             pipeline_step: third_step)
    end
    let!(:expired_pending_token) do
      create(:ci_cd_step_approval_token,
             step_execution: third_execution,
             status: 'pending',
             expires_at: 1.day.ago)
    end

    describe '.pending' do
      it 'returns only pending tokens' do
        expect(described_class.pending).to include(pending_token, expired_pending_token)
        expect(described_class.pending).not_to include(approved_token)
      end
    end

    describe '.active' do
      it 'returns pending tokens not yet expired' do
        expect(described_class.active).to include(pending_token)
        expect(described_class.active).not_to include(approved_token, expired_pending_token)
      end
    end

    describe '.expired_tokens' do
      it 'returns pending tokens that have expired' do
        expect(described_class.expired_tokens).to include(expired_pending_token)
        expect(described_class.expired_tokens).not_to include(pending_token, approved_token)
      end
    end

    describe '.for_step_execution' do
      it 'returns tokens for specific step execution' do
        expect(described_class.for_step_execution(step_execution.id)).to include(pending_token)
        expect(described_class.for_step_execution(step_execution.id)).not_to include(approved_token, expired_pending_token)
      end
    end
  end

  describe '.create_for_recipient' do
    it 'creates a token with hashed digest and returns raw token' do
      token, raw_token = described_class.create_for_recipient(
        step_execution: step_execution,
        recipient_email: 'approver@example.com',
        expires_in: 24.hours
      )

      expect(token).to be_persisted
      expect(token.recipient_email).to eq('approver@example.com')
      expect(token.status).to eq('pending')
      expect(token.expires_at).to be_within(1.minute).of(24.hours.from_now)
      expect(raw_token).to be_present
      expect(raw_token.length).to be >= 32

      # Verify the raw token hashes to the stored digest
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
    end

    it 'associates recipient_user if provided' do
      user = create(:user, account: account)
      token, _raw = described_class.create_for_recipient(
        step_execution: step_execution,
        recipient_email: user.email,
        recipient_user: user,
        expires_in: 24.hours
      )

      expect(token.recipient_user).to eq(user)
    end

    it 'defaults to 24 hour expiry when not specified' do
      token, _raw = described_class.create_for_recipient(
        step_execution: step_execution,
        recipient_email: 'approver@example.com'
      )

      expect(token.expires_at).to be_within(1.minute).of(24.hours.from_now)
    end
  end

  describe '.find_by_token' do
    it 'returns nil for non-existent token' do
      expect(described_class.find_by_token('nonexistent')).to be_nil
    end

    it 'returns nil for blank token' do
      expect(described_class.find_by_token('')).to be_nil
      expect(described_class.find_by_token(nil)).to be_nil
    end

    it 'finds token by raw token value' do
      created_token, raw_token = described_class.create_for_recipient(
        step_execution: step_execution,
        recipient_email: 'approver@example.com'
      )

      found = described_class.find_by_token(raw_token)
      expect(found).to eq(created_token)
    end
  end

  describe '.generate_digest' do
    it 'generates consistent SHA256 digest' do
      raw_token = 'test_token_12345'
      digest1 = described_class.generate_digest(raw_token)
      digest2 = described_class.generate_digest(raw_token)

      expect(digest1).to eq(digest2)
      expect(digest1).to eq(Digest::SHA256.hexdigest(raw_token))
    end
  end

  describe '#approve!' do
    let(:approving_user) { create(:user, account: account) }
    let!(:token) do
      token, @raw_token = described_class.create_for_recipient(
        step_execution: step_execution,
        recipient_email: 'approver@example.com'
      )
      token
    end

    before do
      # Mock handle_approval_response! on step_execution to avoid triggering full workflow logic
      allow(step_execution).to receive(:handle_approval_response!).and_return(true)
    end

    it 'marks token as approved' do
      result = token.approve!(by_user: approving_user, comment: 'Looks good!')

      expect(result).to be true
      expect(token.reload.status).to eq('approved')
      expect(token.responded_by).to eq(approving_user)
      expect(token.response_comment).to eq('Looks good!')
      expect(token.responded_at).to be_present
    end

    it 'calls handle_approval_response! on step execution with approved=true' do
      expect(step_execution).to receive(:handle_approval_response!).with(
        approved: true,
        comment: 'LGTM',
        by_user: approving_user
      )

      token.approve!(by_user: approving_user, comment: 'LGTM')
    end

    it 'returns false if token is not pending' do
      token.update!(status: 'expired')

      result = token.approve!(by_user: approving_user)
      expect(result).to be false
    end

    it 'returns false if token is already expired by time' do
      token.update!(expires_at: 1.hour.ago)

      result = token.approve!(by_user: approving_user)
      expect(result).to be false
    end

    it 'works without a user' do
      result = token.approve!(comment: 'Approved via email link')

      expect(result).to be true
      expect(token.reload.status).to eq('approved')
      expect(token.responded_by).to be_nil
      expect(token.response_comment).to eq('Approved via email link')
    end
  end

  describe '#reject!' do
    let(:rejecting_user) { create(:user, account: account) }
    let!(:token) do
      token, @raw_token = described_class.create_for_recipient(
        step_execution: step_execution,
        recipient_email: 'approver@example.com'
      )
      token
    end

    before do
      allow(step_execution).to receive(:handle_approval_response!).and_return(true)
    end

    it 'marks token as rejected' do
      result = token.reject!(by_user: rejecting_user, comment: 'Needs more work')

      expect(result).to be true
      expect(token.reload.status).to eq('rejected')
      expect(token.responded_by).to eq(rejecting_user)
      expect(token.response_comment).to eq('Needs more work')
      expect(token.responded_at).to be_present
    end

    it 'calls handle_approval_response! with approved=false on step execution' do
      expect(step_execution).to receive(:handle_approval_response!).with(
        approved: false,
        comment: 'Not ready',
        by_user: rejecting_user
      )

      token.reject!(by_user: rejecting_user, comment: 'Not ready')
    end

    it 'returns false if token is not pending' do
      token.update!(status: 'approved')

      result = token.reject!(by_user: rejecting_user)
      expect(result).to be false
    end

    it 'returns false if token is already expired' do
      token.update!(expires_at: 1.hour.ago)

      result = token.reject!(by_user: rejecting_user)
      expect(result).to be false
    end
  end

  describe '#expire!' do
    let!(:token) { create(:ci_cd_step_approval_token, step_execution: step_execution) }

    it 'marks token as expired' do
      token.expire!
      expect(token.reload.status).to eq('expired')
    end

    it 'returns false if token is not pending' do
      token.update!(status: 'approved')
      expect(token.expire!).to be false
    end
  end

  describe '#can_respond?' do
    let!(:token) { create(:ci_cd_step_approval_token, step_execution: step_execution) }

    it 'returns true for pending token with future expiry' do
      expect(token.can_respond?).to be true
    end

    it 'returns false for non-pending token' do
      token.update!(status: 'approved')
      expect(token.can_respond?).to be false
    end

    it 'returns false for expired token' do
      token.update!(expires_at: 1.hour.ago)
      expect(token.can_respond?).to be false
    end
  end

  describe '#pending?' do
    it 'returns true for pending status' do
      token = build(:ci_cd_step_approval_token, status: 'pending')
      expect(token.pending?).to be true
    end

    it 'returns false for non-pending status' do
      token = build(:ci_cd_step_approval_token, status: 'approved')
      expect(token.pending?).to be false
    end
  end

  describe '#approved?' do
    it 'returns true for approved status' do
      token = build(:ci_cd_step_approval_token, status: 'approved')
      expect(token.approved?).to be true
    end

    it 'returns false for non-approved status' do
      token = build(:ci_cd_step_approval_token, status: 'pending')
      expect(token.approved?).to be false
    end
  end

  describe '#rejected?' do
    it 'returns true for rejected status' do
      token = build(:ci_cd_step_approval_token, status: 'rejected')
      expect(token.rejected?).to be true
    end

    it 'returns false for non-rejected status' do
      token = build(:ci_cd_step_approval_token, status: 'pending')
      expect(token.rejected?).to be false
    end
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      token = build(:ci_cd_step_approval_token,
                    step_execution: step_execution,
                    expires_at: 1.hour.ago)
      expect(token.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      token = build(:ci_cd_step_approval_token,
                    step_execution: step_execution,
                    expires_at: 1.hour.from_now)
      expect(token.expired?).to be false
    end
  end

  describe '#time_remaining' do
    it 'returns positive seconds when not expired' do
      token = build(:ci_cd_step_approval_token,
                    step_execution: step_execution,
                    expires_at: 1.hour.from_now)
      expect(token.time_remaining).to be_within(60).of(3600)
    end

    it 'returns 0 when expired' do
      token = build(:ci_cd_step_approval_token,
                    step_execution: step_execution,
                    expires_at: 1.hour.ago)
      expect(token.time_remaining).to eq(0)
    end
  end

  describe '#email_context' do
    let!(:token) { create(:ci_cd_step_approval_token, step_execution: step_execution) }

    it 'returns context hash for email template' do
      context = token.email_context

      expect(context[:token_id]).to eq(token.id)
      expect(context[:recipient_email]).to eq(token.recipient_email)
      expect(context[:step_name]).to eq(pipeline_step.name)
      expect(context[:pipeline_name]).to eq(pipeline.name)
      expect(context[:run_number]).to eq(pipeline_run.run_number)
      expect(context[:trigger_type]).to eq(pipeline_run.trigger_type)
      expect(context[:expires_at]).to eq(token.expires_at)
      expect(context[:timeout_hours]).to be_present
    end
  end

  describe 'callbacks' do
    describe '#set_default_expiry' do
      it 'sets expiry based on step approval_settings' do
        step_with_custom_timeout = create(:ci_cd_pipeline_step,
                                           pipeline: pipeline,
                                           name: 'Custom Timeout Step',
                                           requires_approval: true,
                                           approval_settings: { 'timeout_hours' => 48 })
        execution_with_custom = create(:ci_cd_step_execution,
                                        :waiting_approval,
                                        pipeline_run: pipeline_run,
                                        pipeline_step: step_with_custom_timeout)

        token = build(:ci_cd_step_approval_token,
                      step_execution: execution_with_custom,
                      expires_at: nil)
        token.valid?

        expect(token.expires_at).to be_within(1.minute).of(48.hours.from_now)
      end

      it 'defaults to 24 hours if no approval_settings' do
        step_without_timeout = create(:ci_cd_pipeline_step,
                                       pipeline: pipeline,
                                       name: 'No Timeout Step',
                                       requires_approval: true,
                                       approval_settings: {})
        execution_without = create(:ci_cd_step_execution,
                                    :waiting_approval,
                                    pipeline_run: pipeline_run,
                                    pipeline_step: step_without_timeout)

        token = build(:ci_cd_step_approval_token,
                      step_execution: execution_without,
                      expires_at: nil)
        token.valid?

        expect(token.expires_at).to be_within(1.minute).of(24.hours.from_now)
      end
    end
  end
end
