# frozen_string_literal: true

require 'rails_helper'

# IMP-bf52b4da135b — DELETABLE_DATA_TYPES is the platform's advertisement of
# which GDPR Article 17 categories a data subject can actually have erased.
# It listed nine; three ('files', 'activity', 'analytics') had no erasure
# path, so a request naming one could never be honoured and was silently
# recorded as skipped. Operator direction: every advertised type must have a
# real erasure backend or be withdrawn from the offer. Those three are
# withdrawn — see the constant's own comment for the per-type reasoning,
# which differs ('files' has a backing model but no SAFE erasure path;
# 'activity'/'analytics' have no category-level path at all).
#
# Withdrawing them from the constant alone would be inert: nothing read the
# constant, and Api::V1::PrivacyController#request_deletion permits an
# arbitrary `data_types_to_delete` array. The validation below is what makes
# the withdrawal observable to a caller instead of a silent no-op.
RSpec.describe DataManagement::DeletionRequest, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'DELETABLE_DATA_TYPES' do
    it 'only advertises data types that have a backing erasure path' do
      expect(described_class::DELETABLE_DATA_TYPES).to contain_exactly(
        'profile', 'audit_logs', 'payments', 'settings', 'consents', 'communications'
      )
    end

    it 'no longer advertises the withdrawn types' do
      # 'files' has a backing model but no correct erasure path yet;
      # 'activity'/'analytics' have no category-level erasure path at all.
      # See the constant's own comment for the per-type reasoning.
      expect(described_class::DELETABLE_DATA_TYPES).not_to include('files')
      expect(described_class::DELETABLE_DATA_TYPES).not_to include('activity')
      expect(described_class::DELETABLE_DATA_TYPES).not_to include('analytics')
    end
  end

  describe 'data_types_to_delete validation' do
    it 'accepts every advertised data type' do
      request = build(
        :data_management_deletion_request,
        account: account,
        user: user,
        data_types_to_delete: described_class::DELETABLE_DATA_TYPES
      )

      expect(request).to be_valid
    end

    it 'accepts an empty selection' do
      request = build(
        :data_management_deletion_request,
        account: account,
        user: user,
        data_types_to_delete: []
      )

      expect(request).to be_valid
    end

    it 'rejects a withdrawn data type' do
      request = build(
        :data_management_deletion_request,
        account: account,
        user: user,
        data_types_to_delete: %w[profile analytics]
      )

      expect(request).not_to be_valid
      expect(request.errors[:data_types_to_delete].join).to include('analytics')
    end

    it 'rejects a data type that was never advertised' do
      request = build(
        :data_management_deletion_request,
        account: account,
        user: user,
        data_types_to_delete: %w[everything]
      )

      expect(request).not_to be_valid
    end

    # The validation is create-only on purpose. The worker PATCHes a request
    # repeatedly while processing it (status, deletion_log, retention_log —
    # Compliance::DataDeletionJob#patch_deletion_request!), and rows created
    # before this withdrawal can legitimately still carry 'activity' or
    # 'analytics'. Validating on update would 422 every one of those status
    # writes and strand the request mid-flight — the exact failure mode
    # IMP-b33a3ecca331 had to repair.
    it 'does not block a status write on a pre-existing row holding a withdrawn type' do
      request = build(
        :data_management_deletion_request,
        account: account,
        user: user,
        data_types_to_delete: %w[profile analytics]
      )
      request.save!(validate: false)

      expect(request.update(status: 'processing')).to be true
    end
  end

  # IMP-26adf1c79c7a — the grace period is the data subject's cancellation
  # window. The rule lives here, once: a request may start processing only
  # when it is approved AND its grace period has verifiably ended. A blank end
  # date fails CLOSED (an absent date is not "already ended").
  describe '#can_start_processing? / #start_processing!' do
    def request_with(status:, grace_period_ends_at:)
      create(:data_management_deletion_request, account: account, user: user,
                                                status: status, grace_period_ends_at: grace_period_ends_at)
    end

    it 'is false inside the grace period' do
      request = request_with(status: 'approved', grace_period_ends_at: 1.day.from_now)

      expect(request.can_start_processing?).to be false
    end

    it 'is true once the grace period has ended' do
      request = request_with(status: 'approved', grace_period_ends_at: 1.second.ago)

      expect(request.can_start_processing?).to be true
    end

    it 'is false (fails closed) on a blank grace_period_ends_at' do
      request = request_with(status: 'approved', grace_period_ends_at: nil)

      expect(request.can_start_processing?).to be false
    end

    %w[pending processing completed failed rejected cancelled].each do |status|
      it "is false for a #{status} request even with an ended grace period" do
        request = request_with(status: status, grace_period_ends_at: 1.day.ago)

        expect(request.can_start_processing?).to be false
      end
    end

    it 'start_processing! moves an eligible request to processing and stamps processing_started_at' do
      request = request_with(status: 'approved', grace_period_ends_at: 1.day.ago)

      expect(request.start_processing!).to be true
      expect(request.reload.status).to eq('processing')
      expect(request.processing_started_at).to be_present
    end

    it 'start_processing! refuses inside the grace period and leaves the row untouched' do
      request = request_with(status: 'approved', grace_period_ends_at: 1.day.from_now)

      expect(request.start_processing!).to be false
      expect(request.reload.status).to eq('approved')
      expect(request.processing_started_at).to be_nil
    end

    it 'start_processing! refuses on a blank grace_period_ends_at and leaves the row untouched' do
      request = request_with(status: 'approved', grace_period_ends_at: nil)

      expect(request.start_processing!).to be false
      expect(request.reload.status).to eq('approved')
    end

    # Two starters (run-now + worker, or two run-nows) each hold an instance
    # that read the row as 'approved'. The second must re-check under the row
    # lock, see 'processing', and refuse: at most one start.
    it 'start_processing! starts at most once across two stale instances' do
      request = request_with(status: 'approved', grace_period_ends_at: 1.day.ago)
      first = described_class.find(request.id)
      second = described_class.find(request.id)

      expect(first.start_processing!).to be true
      expect(second.approved?).to be true
      expect(second.start_processing!).to be false
      expect(request.reload.status).to eq('processing')
    end
  end
end
