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
end
