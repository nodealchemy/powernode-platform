# frozen_string_literal: true

require 'rails_helper'

# IMP-b719328ddeb9 — the address a GDPR completion notice goes to must be
# captured while the user still has one. The erasure this request performs
# anonymizes the user record (email included), so any address read AFTER the
# erasure is an anonymized placeholder or nil. The request therefore carries a
# snapshot, taken at creation, encrypted at rest, and scrubbed the moment the
# request reaches a terminal status (a snapshot that outlived the data it
# describes would itself be personal data kept after erasure).
RSpec.describe DataManagement::DeletionRequest, 'notification email snapshot', type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    allow(AuditLog).to receive(:log_compliance_event).and_return(true)
    allow(NotificationService).to receive(:send_email).and_return(true)
    allow(Notification).to receive(:create).and_return(Notification.new)
  end

  def anonymize!(target)
    target.update_columns(email: User.anonymized_email_for(target.id))
  end

  def raw_column(request)
    described_class.connection.select_value(
      "SELECT notification_email FROM data_deletion_requests WHERE id = '#{request.id}'"
    )
  end

  describe 'capture' do
    it "snapshots the user's email when the request is created" do
      request = create(:data_management_deletion_request, account: account, user: user)

      expect(request.reload.notification_email).to eq(user.email)
    end

    it 'keeps the snapshot when the user later changes their email (snapshot at creation, not refresh)' do
      request = create(:data_management_deletion_request, account: account, user: user)
      original = user.email
      user.update_columns(email: 'changed-after-request@example.test')

      expect(request.reload.notification_email).to eq(original)
    end

    it 'stores the snapshot encrypted at rest' do
      request = create(:data_management_deletion_request, account: account, user: user)

      expect(raw_column(request)).to be_present
      expect(raw_column(request)).not_to include(user.email)
    end

    it 'does not snapshot the placeholder of an already-anonymized user' do
      anonymize!(user)

      request = create(:data_management_deletion_request, account: account, user: user)

      expect(request.reload.notification_email).to be_nil
    end

    it 'does not snapshot for a row created already terminal' do
      request = create(:data_management_deletion_request, account: account, user: user, status: 'completed')

      expect(request.reload.notification_email).to be_nil
    end
  end

  describe 'scrub' do
    %w[completed failed rejected cancelled].each do |terminal|
      it "clears the snapshot in the same write that moves the request to #{terminal}" do
        request = create(:data_management_deletion_request, account: account, user: user, status: 'processing')
        expect(request.notification_email).to be_present

        request.update!(status: terminal)

        expect(raw_column(request)).to be_nil
      end
    end

    it 'keeps the snapshot while the request is still in flight' do
      request = create(:data_management_deletion_request, account: account, user: user, status: 'approved',
                                                          grace_period_ends_at: 1.day.ago)
      request.start_processing!

      expect(request.reload.notification_email).to eq(user.email)
    end
  end

  describe '#complete! notification' do
    it 'sends to the snapshot address even after the user email has been erased' do
      request = create(:data_management_deletion_request, account: account, user: user, status: 'processing')
      snapshot = request.notification_email
      anonymize!(user)

      request.complete!(deletion_log: [])

      expect(NotificationService).to have_received(:send_email)
        .with(hash_including(template: 'data_deletion_complete', email: snapshot))
      expect(raw_column(request)).to be_nil
    end

    it 'sends nothing, warns, and still completes when there is no snapshot' do
      request = create(:data_management_deletion_request, account: account, user: user, status: 'processing')
      request.update_columns(notification_email: nil)
      allow(Rails.logger).to receive(:warn)

      expect { request.complete!(deletion_log: []) }.not_to raise_error

      expect(request.reload.status).to eq('completed')
      expect(NotificationService).not_to have_received(:send_email)
        .with(hash_including(template: 'data_deletion_complete'))
      expect(Rails.logger).to have_received(:warn).with(/no notification address/i)
    end
  end

  describe 'serialization' do
    it 'never carries the snapshot in a generic serialization' do
      request = create(:data_management_deletion_request, account: account, user: user)

      expect(request.as_json).not_to have_key('notification_email')
      expect(request.to_json).not_to include(user.email)
    end

    it 'keeps the snapshot out of #inspect' do
      request = create(:data_management_deletion_request, account: account, user: user)

      expect(request.inspect).not_to include(user.email)
    end
  end
end
