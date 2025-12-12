# frozen_string_literal: true

# ApplicationJob - Legacy job base class
#
# NOTE: All background jobs have been migrated to the standalone worker service
# located in ./worker/app/jobs/. This class remains for backward compatibility
# but should not be used for new jobs.
#
# For new background jobs, create them in the worker service:
# - Billing jobs: ./worker/app/jobs/billing/
# - Report jobs: ./worker/app/jobs/reports/
# - Webhook jobs: ./worker/app/jobs/webhooks/
# - Analytics jobs: ./worker/app/jobs/analytics/
#
class ApplicationJob < ActiveJob::Base
  # This class is deprecated - use worker service instead

  def self.inherited(subclass)
    super
    Rails.logger.warn "WARNING: #{subclass.name} inherits from ApplicationJob which is deprecated. " \
                      "Please migrate background jobs to the standalone worker service."
  end

  # Legacy configuration kept for compatibility
  # retry_on ActiveRecord::Deadlocked
  # discard_on ActiveJob::DeserializationError
end
