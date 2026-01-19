# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorkflowApprovalToken, type: :model do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }
  let(:workflow_run) { create(:ai_workflow_run, workflow: workflow) }
  let(:workflow_node) { create(:ai_workflow_node, workflow: workflow) }
  let(:node_execution) do
    create(:ai_workflow_node_execution,
           workflow_run: workflow_run,
           node: workflow_node,
           status: 'waiting_approval')
  end

  describe 'associations' do
    it { is_expected.to belong_to(:node_execution) }
    it { is_expected.to belong_to(:recipient_user).class_name('User').optional }
    it { is_expected.to belong_to(:responded_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:ai_workflow_approval_token, node_execution: node_execution) }

    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_presence_of(:recipient_email) }
    # Note: expires_at is auto-set by before_validation callback, so we test the callback instead
    it 'auto-sets expires_at if not provided' do
      token = build(:ai_workflow_approval_token, node_execution: node_execution, expires_at: nil)
      token.valid?
      expect(token.expires_at).to be_present
    end

    it 'validates email format' do
      token = build(:ai_workflow_approval_token,
                    node_execution: node_execution,
                    recipient_email: 'invalid-email')
      expect(token).not_to be_valid
      expect(token.errors[:recipient_email]).to be_present
    end

    it 'validates status inclusion' do
      valid_statuses = %w[pending approved rejected expired]
      valid_statuses.each do |status|
        token = build(:ai_workflow_approval_token,
                      node_execution: node_execution,
                      status: status)
        token.token_digest = SecureRandom.hex(32)
        expect(token).to be_valid, "Expected status '#{status}' to be valid"
      end
    end

    it 'validates token_digest uniqueness' do
      existing_token = create(:ai_workflow_approval_token, node_execution: node_execution)
      duplicate_token = build(:ai_workflow_approval_token,
                              node_execution: node_execution,
                              token_digest: existing_token.token_digest)
      expect(duplicate_token).not_to be_valid
      expect(duplicate_token.errors[:token_digest]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:pending_token) do
      create(:ai_workflow_approval_token,
             node_execution: node_execution,
             status: 'pending',
             expires_at: 1.day.from_now)
    end
    let!(:approved_token) do
      create(:ai_workflow_approval_token,
             node_execution: node_execution,
             status: 'approved',
             expires_at: 1.day.from_now)
    end
    let!(:expired_pending_token) do
      create(:ai_workflow_approval_token,
             node_execution: node_execution,
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

    describe '.for_node_execution' do
      # Create a different workflow node for the other execution to avoid unique constraint
      let(:other_workflow_node) { create(:ai_workflow_node, workflow: workflow) }
      let(:other_execution) { create(:ai_workflow_node_execution, workflow_run: workflow_run, node: other_workflow_node) }
      let!(:other_token) { create(:ai_workflow_approval_token, node_execution: other_execution) }

      it 'returns tokens for specific node execution' do
        expect(described_class.for_node_execution(node_execution.id))
          .to include(pending_token, approved_token, expired_pending_token)
        expect(described_class.for_node_execution(node_execution.id))
          .not_to include(other_token)
      end
    end
  end

  describe '.create_for_recipient' do
    it 'creates a token with hashed digest and returns raw token' do
      token, raw_token = described_class.create_for_recipient(
        node_execution: node_execution,
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
        node_execution: node_execution,
        recipient_email: user.email,
        recipient_user: user,
        expires_in: 24.hours
      )

      expect(token.recipient_user).to eq(user)
    end

    it 'defaults to 24 hour expiry when not specified' do
      token, _raw = described_class.create_for_recipient(
        node_execution: node_execution,
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
        node_execution: node_execution,
        recipient_email: 'approver@example.com'
      )

      found = described_class.find_by_token(raw_token)
      expect(found).to eq(created_token)
    end
  end

  describe '#approve!' do
    let(:approving_user) { create(:user, account: account) }
    let!(:token) do
      token, @raw_token = described_class.create_for_recipient(
        node_execution: node_execution,
        recipient_email: 'approver@example.com'
      )
      token
    end

    before do
      # Mock approve_execution! on node_execution to avoid triggering full workflow logic
      allow(node_execution).to receive(:approve_execution!).and_return(true)
    end

    it 'marks token as approved' do
      result = token.approve!(by_user: approving_user, comment: 'Looks good!')

      expect(result).to be true
      expect(token.reload.status).to eq('approved')
      expect(token.responded_by).to eq(approving_user)
      expect(token.response_comment).to eq('Looks good!')
      expect(token.responded_at).to be_present
    end

    it 'calls approve_execution! on node execution' do
      expect(node_execution).to receive(:approve_execution!).with(
        approving_user.id,
        hash_including('approved' => true)
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
  end

  describe '#reject!' do
    let(:rejecting_user) { create(:user, account: account) }
    let!(:token) do
      token, @raw_token = described_class.create_for_recipient(
        node_execution: node_execution,
        recipient_email: 'approver@example.com'
      )
      token
    end

    before do
      allow(node_execution).to receive(:approve_execution!).and_return(true)
    end

    it 'marks token as rejected' do
      result = token.reject!(by_user: rejecting_user, comment: 'Needs more work')

      expect(result).to be true
      expect(token.reload.status).to eq('rejected')
      expect(token.responded_by).to eq(rejecting_user)
      expect(token.response_comment).to eq('Needs more work')
      expect(token.responded_at).to be_present
    end

    it 'calls approve_execution! with approved=false on node execution' do
      expect(node_execution).to receive(:approve_execution!).with(
        rejecting_user.id,
        hash_including('approved' => false)
      )

      token.reject!(by_user: rejecting_user, comment: 'Not ready')
    end

    it 'returns false if token is not pending' do
      token.update!(status: 'approved')

      result = token.reject!(by_user: rejecting_user)
      expect(result).to be false
    end
  end

  describe '#expire!' do
    let!(:token) { create(:ai_workflow_approval_token, node_execution: node_execution) }

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
    let!(:token) { create(:ai_workflow_approval_token, node_execution: node_execution) }

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

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      token = build(:ai_workflow_approval_token,
                    node_execution: node_execution,
                    expires_at: 1.hour.ago)
      expect(token.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      token = build(:ai_workflow_approval_token,
                    node_execution: node_execution,
                    expires_at: 1.hour.from_now)
      expect(token.expired?).to be false
    end
  end

  describe '#time_remaining' do
    it 'returns positive seconds when not expired' do
      token = build(:ai_workflow_approval_token,
                    node_execution: node_execution,
                    expires_at: 1.hour.from_now)
      expect(token.time_remaining).to be_within(60).of(3600)
    end

    it 'returns 0 when expired' do
      token = build(:ai_workflow_approval_token,
                    node_execution: node_execution,
                    expires_at: 1.hour.ago)
      expect(token.time_remaining).to eq(0)
    end
  end

  describe '#email_context' do
    let!(:token) { create(:ai_workflow_approval_token, node_execution: node_execution) }

    before do
      node_execution.update!(metadata: { 'approval_message' => 'Please approve this workflow step' })
    end

    it 'returns context hash for email template' do
      context = token.email_context

      expect(context[:token_id]).to eq(token.id)
      expect(context[:recipient_email]).to eq(token.recipient_email)
      expect(context[:workflow_name]).to eq(workflow.name)
      expect(context[:run_id]).to eq(workflow_run.run_id)
      expect(context[:approval_message]).to eq('Please approve this workflow step')
      expect(context[:expires_at]).to eq(token.expires_at)
    end
  end

  describe 'status predicates' do
    let!(:token) { create(:ai_workflow_approval_token, node_execution: node_execution) }

    it 'pending? returns true for pending status' do
      expect(token.pending?).to be true
    end

    it 'approved? returns true for approved status' do
      token.update!(status: 'approved')
      expect(token.approved?).to be true
    end

    it 'rejected? returns true for rejected status' do
      token.update!(status: 'rejected')
      expect(token.rejected?).to be true
    end
  end
end
