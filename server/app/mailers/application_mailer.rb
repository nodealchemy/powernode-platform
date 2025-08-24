# frozen_string_literal: true

# This file is kept for Rails compatibility
# All mailer functionality has been moved to the worker service
class ApplicationMailer < ActionMailer::Base
  default from: "noreply@powernode.dev"
  layout "mailer"
  
  # Prevent accidental usage - all emails should go through worker service
  def self.method_missing(method_name, *args, &block)
    Rails.logger.warn "Attempted to use backend mailer #{method_name}. Use WorkerJobService instead."
    raise NotImplementedError, "Mailer functionality moved to worker service. Use WorkerJobService.enqueue_notification_email instead."
  end
end
