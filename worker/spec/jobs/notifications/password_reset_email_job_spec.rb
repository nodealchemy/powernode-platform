# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::PasswordResetEmailJob, type: :job do
  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow_logging_methods
  end

  let(:job) { described_class.new }
  let(:mailer) { double('NotificationMailer#password_reset') }
  let(:message) { double('Mail::Message', message_id: 'mid-reset@mail') }

  before { allow(mailer).to receive(:deliver_now).and_return(message) }

  describe 'job configuration' do
    it 'uses the email queue with retry 3' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('email')
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  it 'forwards the plaintext reset token to the mailer' do
    # The token cannot be re-fetched (the server stores only a BCrypt digest),
    # so it must arrive as a job argument or the reset URL is built blank.
    expect(NotificationMailer).to receive(:password_reset)
      .with('user-1', 'plain-token').and_return(mailer)

    result = job.execute('user-1', 'plain-token')

    expect(result[:success]).to be true
    expect(result[:message_id]).to eq('mid-reset@mail')
  end

  it 'still delivers when no token is supplied (legacy one-arg enqueue)' do
    expect(NotificationMailer).to receive(:password_reset).with('user-1', nil).and_return(mailer)

    expect(job.execute('user-1')[:success]).to be true
  end

  it 're-raises a delivery failure so Sidekiq retries it' do
    allow(NotificationMailer).to receive(:password_reset).and_return(mailer)
    allow(mailer).to receive(:deliver_now).and_raise(StandardError, 'smtp down')

    expect { job.execute('user-1', 'plain-token') }.to raise_error(StandardError, 'smtp down')
  end
end
