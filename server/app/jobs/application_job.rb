# frozen_string_literal: true

# Base job class for background jobs
# These jobs are stubs for enqueuing to Sidekiq
# Actual implementations are in the worker service
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
