# frozen_string_literal: true

require 'rails_helper'

# Router for the account-lifecycle emails. Its contract is the ARGUMENT SHAPE the
# server sends (WorkerJobService.enqueue_notification_email): a type string plus
# an options hash whose keys become the mailer action's positional arguments.
RSpec.describe Notifications::NotificationEmailJob, type: :job do
  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow_logging_methods
  end

  let(:job) { described_class.new }
  let(:mailer) { double('NotificationMailer action') }
  let(:message) { double('Mail::Message', message_id: 'mid-abc@mail') }

  before do
    allow(mailer).to receive(:deliver_now).and_return(message)
  end

  describe 'job configuration' do
    it 'uses the email queue with retry 3' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('email')
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe 'dispatch by notification type' do
    # Only the id travels: the invite token is plaintext in the DB, so the
    # mailer reads it from the internal API rather than taking it as a job arg
    # (job args are logged twice and persisted in the Sidekiq/Redis payload).
    it 'routes invitation to invitation_email with the id alone' do
      expect(NotificationMailer).to receive(:invitation_email)
        .with('inv-1').and_return(mailer)

      result = job.execute('invitation', 'invitation_id' => 'inv-1')

      expect(result[:success]).to be true
      expect(result[:message_id]).to eq('mid-abc@mail')
    end

    it 'routes welcome to welcome_email with the user id' do
      expect(NotificationMailer).to receive(:welcome_email).with('user-1').and_return(mailer)

      expect(job.execute('welcome',
        'user_id' => 'user-1', 'email' => 'a@b.test', 'user_name' => 'A B')[:success]).to be true
    end

    it 'routes email_verification to email_verification with the user id alone' do
      expect(NotificationMailer).to receive(:email_verification)
        .with('user-1').and_return(mailer)

      expect(job.execute('email_verification', 'user_id' => 'user-1')[:success]).to be true
    end

    it 'accepts symbol-keyed options (pre-JSON producer shape)' do
      expect(NotificationMailer).to receive(:welcome_email).with('user-1').and_return(mailer)

      expect(job.execute('welcome', user_id: 'user-1')[:success]).to be true
    end
  end

  describe 'failure handling' do
    it 'raises for an unknown type rather than reporting a fake success' do
      # Returning { success: false } here would let Sidekiq mark the job
      # SUCCEEDED — the exact silence this job exists to end.
      expect(NotificationMailer).not_to receive(:welcome_email)

      expect { job.execute('no_such_type', 'user_id' => 'user-1') }
        .to raise_error(ArgumentError, /no_such_type/)
    end

    it 'raises when a required option for the type is missing' do
      expect {
        job.execute('invitation', {})
      }.to raise_error(ArgumentError, /invitation_id/)
    end

    it 're-raises a delivery failure so Sidekiq retries it' do
      allow(NotificationMailer).to receive(:welcome_email).and_return(mailer)
      allow(mailer).to receive(:deliver_now).and_raise(StandardError, 'smtp down')

      expect { job.execute('welcome', 'user_id' => 'user-1') }
        .to raise_error(StandardError, 'smtp down')
    end
  end

  describe 'template coverage' do
    # Every routed action must have an ERB template: routing to a template-less
    # mailer action would turn a silent dead path into ActionView::MissingTemplate.
    it 'has a view template for every dispatched mailer action' do
      views = File.expand_path('../../../app/views/notification_mailer', __dir__)

      described_class::DISPATCH.each_value do |(action, _keys)|
        expect(Dir[File.join(views, "#{action}.*.erb")]).not_to be_empty,
          "NotificationMailer##{action} is routed by #{described_class} but has no ERB template"
      end
    end
  end
end
