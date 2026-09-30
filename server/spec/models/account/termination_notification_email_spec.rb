# frozen_string_literal: true

require 'rails_helper'

# IMP-b719328ddeb9 — by the time an account termination completes, its owner is
# ALREADY ANONYMIZED (the termination job anonymizes every account user before
# it marks the termination complete). The completion notice therefore goes to
# an address snapshotted onto the termination at request time, encrypted at
# rest and scrubbed the moment the termination reaches a terminal status.
RSpec.describe Account::Termination, 'notification email snapshot', type: :model do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, :owner, account: account) }

  before do
    allow(NotificationService).to receive(:send_email).and_return(true)
    allow(AuditLog).to receive(:log_compliance_event).and_return(true)
  end

  def anonymize!(target)
    target.update_columns(email: "deleted_#{target.id}@anonymized.local")
  end

  def raw_column(termination)
    described_class.connection.select_value(
      "SELECT notification_email FROM account_terminations WHERE id = '#{termination.id}'"
    )
  end

  def create_termination(status: 'grace_period')
    described_class.create!(account: account, requested_by: owner, status: status,
                            requested_at: 31.days.ago, grace_period_ends_at: 1.day.ago)
  end

  describe 'capture' do
    it "snapshots the account owner's email when the termination is created" do
      termination = described_class.initiate(account: account, requested_by: owner)

      expect(termination.reload.notification_email).to eq(owner.email)
    end

    it 'stores the snapshot encrypted at rest' do
      termination = described_class.initiate(account: account, requested_by: owner)

      expect(raw_column(termination)).to be_present
      expect(raw_column(termination)).not_to include(owner.email)
    end

    it 'leaves the snapshot nil when the account has no owner' do
      other = create(:account)
      termination = described_class.initiate(account: other, requested_by: nil)

      expect(termination.reload.notification_email).to be_nil
    end
  end

  describe 'scrub' do
    %w[completed cancelled].each do |terminal|
      it "clears the snapshot in the same write that moves the termination to #{terminal}" do
        termination = create_termination(status: 'processing')
        expect(termination.notification_email).to be_present

        termination.update!(status: terminal)

        expect(raw_column(termination)).to be_nil
      end
    end

    it 'keeps the snapshot while the termination is in flight' do
      termination = create_termination
      termination.update!(status: 'processing')

      expect(termination.reload.notification_email).to eq(owner.email)
    end
  end

  describe '#complete! notification' do
    it 'sends to the snapshot even when the owner is anonymized' do
      termination = create_termination(status: 'processing')
      snapshot = termination.notification_email
      anonymize!(owner)

      termination.complete!

      expect(NotificationService).to have_received(:send_email)
        .with(hash_including(template: 'account_termination_complete', email: snapshot))
      expect(raw_column(termination)).to be_nil
    end

    it 'sends nothing, warns, and still completes when there is no snapshot' do
      termination = create_termination(status: 'processing')
      termination.update_columns(notification_email: nil)
      allow(Rails.logger).to receive(:warn)

      expect(termination.complete!).to be true

      expect(termination.reload.status).to eq('completed')
      expect(NotificationService).not_to have_received(:send_email)
        .with(hash_including(template: 'account_termination_complete'))
      expect(Rails.logger).to have_received(:warn).with(/no notification address/i)
    end
  end

  describe 'serialization' do
    it 'never carries the snapshot in a generic serialization' do
      termination = described_class.initiate(account: account, requested_by: owner)

      expect(termination.as_json).not_to have_key('notification_email')
      expect(termination.to_json).not_to include(owner.email)
    end
  end
end
