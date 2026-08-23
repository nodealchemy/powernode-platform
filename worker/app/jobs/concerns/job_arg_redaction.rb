# frozen_string_literal: true

# Sanitises the context hash Sidekiq hands to its error handlers.
#
# Sidekiq's DEFAULT error handler logs the whole job hash — arguments included —
# through Formatters::Base#format_context, at INFO, on every raised job
# exception (Processor#handle_exception passes `job:`, plus `jobstr:` with the
# raw JSON on the internal-exception path). That is a log sink for job arguments
# entirely separate from the ones BaseJob and JobsController own, and it fires
# exactly when a job carrying a secret keeps failing and retrying.
#
# Sidekiq owns its own logger config (see PowernodeWorker#setup_logging), so an
# app-side formatter cannot intercept this — the context has to be cleaned
# before the handler sees it. config/application.rb wraps the default handlers
# with this.
#
# Lives here (rather than inline in the config block) because
# Sidekiq.configure_server does not run under RSpec, so an inline lambda would
# be shipped untested.
module JobArgRedaction
  module_function

  # Returns a copy of ctx with the raw `jobstr` dropped and the job hash's args
  # passed through the job class's own BaseJob.redact_args. Unknown or
  # non-redacting classes are left alone; never raises.
  def sanitize_context(ctx)
    safe = ctx.is_a?(Hash) ? ctx.dup : {}
    safe.delete(:jobstr)

    job = safe[:job]
    return safe unless job.is_a?(Hash) && job["args"].is_a?(Array)

    klass = resolve(job["class"])
    return safe unless klass.respond_to?(:redact_args)

    safe[:job] = job.merge("args" => klass.redact_args(job["args"]))
    safe
  rescue StandardError
    # A logging path must never be the thing that breaks error reporting.
    # Falling back to dropping the job hash entirely is the safe direction.
    (ctx.is_a?(Hash) ? ctx.dup : {}).tap { |h| h.delete(:jobstr); h.delete(:job) }
  end

  def resolve(class_name)
    Object.const_get(class_name.to_s)
  rescue StandardError
    nil
  end
end
