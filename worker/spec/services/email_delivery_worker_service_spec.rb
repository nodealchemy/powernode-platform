# frozen_string_literal: true

require 'spec_helper'
require_relative '../../app/services/email_delivery_worker_service'

RSpec.describe EmailDeliveryWorkerService do
  subject(:service) { described_class.new }

  before do
    mock_powernode_worker_config
  end

  describe '#deliver_mail (transient vs permanent SMTP failures)' do
    let(:mail) { instance_double(Mail::Message) }

    context 'when delivery succeeds' do
      it 'returns a success result hash' do
        allow(mail).to receive(:deliver!)

        result = service.send(:deliver_mail, mail)

        expect(result[:success]).to be true
      end
    end

    context 'with transient failures (must RAISE so Sidekiq retry fires)' do
      [
        Net::SMTPServerBusy.new('451 4.7.1 Try again later'),
        Net::OpenTimeout.new('execution expired'),
        Net::ReadTimeout.new,
        Errno::ECONNREFUSED.new,
        Errno::ECONNRESET.new,
        SocketError.new('getaddrinfo: Temporary failure in name resolution')
      ].each do |transient_error|
        it "raises TransientDeliveryError for #{transient_error.class}" do
          allow(mail).to receive(:deliver!).and_raise(transient_error)

          expect {
            service.send(:deliver_mail, mail)
          }.to raise_error(described_class::TransientDeliveryError, /#{transient_error.class}/)
        end
      end
    end

    context 'with permanent failures (handled as result hashes, no retry)' do
      {
        Net::SMTPAuthenticationError => /Authentication/,
        Net::SMTPSyntaxError => /Syntax/,
        Net::SMTPFatalError => /Fatal/
      }.each do |error_class, message_matcher|
        it "returns an error result hash for #{error_class}" do
          allow(mail).to receive(:deliver!).and_raise(error_class.new('550 permanent failure'))

          result = service.send(:deliver_mail, mail)

          expect(result[:success]).to be false
          expect(result[:error]).to match(message_matcher)
        end
      end

      it 'returns an error result hash for unrecognized errors' do
        allow(mail).to receive(:deliver!).and_raise(StandardError.new('boom'))

        result = service.send(:deliver_mail, mail)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/boom/)
      end
    end
  end

  describe '#send_email' do
    let(:params) do
      {
        to: 'recipient@example.com',
        subject: 'Subject',
        body: '<p>Hello</p>',
        email_type: 'system_notification',
        account_id: 'acct-1',
        user_id: 'user-1'
      }
    end

    before do
      allow(service).to receive(:create_email_delivery_record).and_return(
        { success: true, data: { 'id' => 'delivery-123' } }
      )
      allow(service).to receive(:update_delivery_record).and_return({ success: true })
      allow(service).to receive(:create_audit_log).and_return({ success: true })
    end

    context 'when delivery succeeds' do
      before { allow_any_instance_of(Mail::Message).to receive(:deliver!) }

      it 'returns a success result and marks the delivery record sent' do
        result = service.send_email(**params)

        expect(result[:success]).to be true
        expect(result.dig(:data, :delivery_id)).to eq('delivery-123')
        expect(service).to have_received(:update_delivery_record)
          .with('delivery-123', 'sent', hash_including(:sent_at))
      end
    end

    context 'when delivery fails transiently' do
      before do
        allow_any_instance_of(Mail::Message).to receive(:deliver!)
          .and_raise(Net::SMTPServerBusy.new('451 4.7.1 Try again later'))
      end

      it 'raises TransientDeliveryError (not swallowed into a result hash)' do
        expect {
          service.send_email(**params)
        }.to raise_error(described_class::TransientDeliveryError)
      end

      it 'marks the delivery record failed before raising' do
        begin
          service.send_email(**params)
        rescue described_class::TransientDeliveryError
          # expected
        end

        expect(service).to have_received(:update_delivery_record)
          .with('delivery-123', 'failed', hash_including(:error_message, :failed_at))
      end
    end

    context 'when delivery fails permanently' do
      before do
        allow_any_instance_of(Mail::Message).to receive(:deliver!)
          .and_raise(Net::SMTPFatalError.new('550 mailbox unavailable'))
      end

      it 'returns a handled error result hash and marks the delivery record failed' do
        result = service.send_email(**params)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/550 mailbox unavailable/)
        expect(service).to have_received(:update_delivery_record)
          .with('delivery-123', 'failed', hash_including(:error_message, :failed_at))
      end
    end
  end

  describe '#send_bulk_emails' do
    it 'records a transient per-recipient failure as a failed result without aborting the batch' do
      allow(service).to receive(:send_email).with(hash_including(to: 'a@example.com'))
        .and_raise(described_class::TransientDeliveryError.new('SMTP busy'))
      allow(service).to receive(:send_email).with(hash_including(to: 'b@example.com'))
        .and_return({ success: true, data: { delivery_id: 'd-2' } })

      result = service.send_bulk_emails(
        recipients: ['a@example.com', 'b@example.com'],
        subject: 'S', body: 'B', email_type: 'system_notification'
      )

      expect(result[:success]).to be true
      expect(result.dig(:data, :summary, :failed)).to eq(1)
      expect(result.dig(:data, :summary, :successful)).to eq(1)
      failed = result.dig(:data, :results).find { |r| r[:email] == 'a@example.com' }
      expect(failed[:success]).to be false
      expect(failed[:error]).to match(/SMTP busy/)
    end
  end
end
