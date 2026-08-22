# frozen_string_literal: true

require 'rails_helper'

# Sidekiq job arguments reach FOUR sinks, and a secret placed in them lands in
# all four:
#   1. JobsController's enqueue line   — "Enqueuing <class> with args: ..."
#   2. BaseJob#perform's start line    — "Starting <class> with args: ..."
#      (plus the runaway-loop "Job args:" dumps)
#   3. Sidekiq's DEFAULT error handler — logs the whole job hash, args included,
#      on every raised exception (config/application.rb wraps it to redact)
#   4. the Sidekiq/Redis job payload   — verbatim, in the retry/dead sets, and
#      rendered by Sidekiq::Web. Nothing at this layer can scrub it.
#
# Before IMP-f2cfaed728c4 the account-lifecycle job classes did not exist, so
# valid_job_class? 422'd every enqueue BEFORE sink 1 and before perform_async —
# nothing was written. Implementing those classes is what made the sinks live,
# so this spec is the guard that came with them.
#
# The oracle is the LOG TEXT and the SERIALIZED PAYLOAD, not "the mailer got the
# token": the mailer receiving it is exactly what we still want.
RSpec.describe 'job argument secret exposure', type: :job do
  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  let(:reset_token) { 'PLAINTEXT-RESET-TOKEN-do-not-log' }
  let(:verification_token) { 'PLAINTEXT-VERIFICATION-TOKEN-do-not-log' }

  # Capture everything BaseJob#perform writes to the log.
  def captured_log(job)
    io = StringIO.new
    allow(job).to receive(:logger).and_return(Logger.new(io))
    yield
    io.string
  end

  describe 'password reset (token has no fetchable source — must ride in args)' do
    let(:job) { Notifications::PasswordResetEmailJob.new }
    let(:mailer) { double('mailer', deliver_now: double(message_id: 'mid')) }

    before { allow(NotificationMailer).to receive(:password_reset).and_return(mailer) }

    it 'declares the token position as sensitive' do
      expect(Notifications::PasswordResetEmailJob.sensitive_arg_indexes).to eq([1])
    end

    it 'keeps the token out of the perform log, masking it instead' do
      log = captured_log(job) { job.perform('user-1', reset_token) }

      expect(log).not_to include(reset_token)
      expect(log).to include('[REDACTED]')
    end

    it 'still hands the real token to the mailer' do
      expect(NotificationMailer).to receive(:password_reset).with('user-1', reset_token).and_return(mailer)

      job.execute('user-1', reset_token)
    end

    it 'masks the token for the enqueue-side log too' do
      redacted = Notifications::PasswordResetEmailJob.redact_args(['user-1', reset_token])

      expect(redacted.inspect).not_to include(reset_token)
      expect(redacted).to eq([ 'user-1', '[REDACTED]' ])
    end

    # Stated plainly: redaction covers the LOG sinks only.
    it 'does NOT scrub the serialized Sidekiq payload (known residual exposure)' do
      Notifications::PasswordResetEmailJob.perform_async('user-1', reset_token)
      payload = Notifications::PasswordResetEmailJob.jobs.last

      expect(payload['args']).to eq([ 'user-1', reset_token ])
    end
  end

  describe 'notification email (tokens are fetchable, so they never enter args)' do
    let(:job) { Notifications::NotificationEmailJob.new }
    let(:described_class_for_hash) { Notifications::NotificationEmailJob }
    let(:mailer) { double('mailer', deliver_now: double(message_id: 'mid')) }

    it 'dispatches ids only — no token key in any DISPATCH entry' do
      keys = Notifications::NotificationEmailJob::DISPATCH.values.flat_map(&:last)

      expect(keys.grep(/token/)).to be_empty
    end

    # NOT a "the token isn't there" assertion — that would pass vacuously against
    # any code, including the old DISPATCH that DID carry tokens. This feeds a
    # token in deliberately and proves the log masks it, so a future producer
    # putting one back into the options hash is caught.
    it 'masks a token smuggled into the options hash' do
      allow(NotificationMailer).to receive(:email_verification).and_return(mailer)

      log = captured_log(job) do
        job.perform('email_verification',
          'user_id' => 'user-1', 'verification_token' => verification_token)
      end

      expect(log).to include('user-1')
      expect(log).not_to include(verification_token)
      expect(log).to include('[REDACTED]')
    end

    it 'masks nested and array-wrapped sensitive keys too' do
      redacted = described_class_for_hash.redact_args(
        [ { 'outer' => { 'api_key' => 'AKIA-nope', 'safe' => 'keep' } } ]
      )

      expect(redacted.inspect).not_to include('AKIA-nope')
      expect(redacted.inspect).to include('keep')
    end
  end

  # The enqueue-side sink lives in JobsController, which reaches redaction via
  # `klass.respond_to?(:redact_args)`. Assert that contract holds for the job
  # classes that go through it — reverting the controller to a bare
  # `args.inspect` is otherwise invisible to every spec.
  describe 'enqueue-side sink contract (JobsController)' do
    it 'exposes redact_args on every BaseJob subclass the controller may see' do
      [ Notifications::PasswordResetEmailJob,
        Notifications::NotificationEmailJob,
        BaseJob ].each do |klass|
        expect(klass).to respond_to(:redact_args)
      end
    end

    it 'masks through the same call the controller makes' do
      klass = Object.const_get('Notifications::PasswordResetEmailJob')
      loggable = klass.respond_to?(:redact_args) ? klass.redact_args([ 'user-1', reset_token ]) : [ 'user-1', reset_token ]

      expect(loggable.inspect).not_to include(reset_token)
    end
  end

  # The runaway-loop dumps are a third log statement inside BaseJob and are
  # never exercised by any other spec (every job spec stubs check_runaway_loop).
  describe 'runaway-loop arg dump' do
    it 'masks the token in the high-frequency warning dump' do
      job = Notifications::PasswordResetEmailJob.new
      io = StringIO.new
      allow(job).to receive(:logger).and_return(Logger.new(io))

      job.send(:log_runaway_args, [ 'user-1', reset_token ])

      expect(io.string).not_to include(reset_token)
      expect(io.string).to include('[REDACTED]')
    end
  end

  # Sink 3: Sidekiq's own error handler. Its context is cleaned by
  # JobArgRedaction before the default handlers log it. Sidekiq.configure_server
  # does not run under RSpec, so this exercises the extracted logic directly —
  # the same call the wrapper in config/application.rb makes.
  describe 'Sidekiq error-handler sink (JobArgRedaction)' do
    let(:ctx) do
      {
        context: 'Job raised exception',
        job: {
          'class' => 'Notifications::PasswordResetEmailJob',
          'args' => [ 'user-1', reset_token ],
          'queue' => 'email'
        },
        jobstr: %({"class":"Notifications::PasswordResetEmailJob","args":["user-1","#{reset_token}"]})
      }
    end

    it 'masks the token in the job hash the handler logs' do
      safe = JobArgRedaction.sanitize_context(ctx)

      expect(safe[:job]['args']).to eq([ 'user-1', '[REDACTED]' ])
      expect(safe.inspect).not_to include(reset_token)
    end

    it 'drops jobstr, which carries the raw unredactable JSON' do
      expect(JobArgRedaction.sanitize_context(ctx)).not_to have_key(:jobstr)
    end

    it 'preserves the rest of the context so error reports stay useful' do
      safe = JobArgRedaction.sanitize_context(ctx)

      expect(safe[:context]).to eq('Job raised exception')
      expect(safe[:job]['queue']).to eq('email')
    end

    it 'leaves a job class it cannot resolve alone rather than raising' do
      safe = JobArgRedaction.sanitize_context(
        ctx.merge(job: { 'class' => 'NoSuchJobAnywhere', 'args' => [ 'x' ] })
      )

      expect(safe[:job]['args']).to eq([ 'x' ])
    end

    it 'tolerates a context with no job at all' do
      expect { JobArgRedaction.sanitize_context({ context: 'boot' }) }.not_to raise_error
    end
  end

  describe 'BaseJob.redact_args' do
    it 'is a no-op for jobs that declare nothing' do
      expect(Notifications::NotificationEmailJob.redact_args(%w[a b])).to eq(%w[a b])
    end

    it 'leaves a nil in a sensitive position alone rather than faking a value' do
      expect(Notifications::PasswordResetEmailJob.redact_args([ 'user-1', nil ]))
        .to eq([ 'user-1', nil ])
    end
  end
end
