# frozen_string_literal: true

# Health check controller for worker service monitoring
class HealthController < ApplicationController
  skip_before_action :authenticate_request

  def index
    render_success({
      status: 'healthy',
      timestamp: Time.current.iso8601,
      uptime_seconds: (Time.current - Rails.application.config.boot_time).round
    })
  end
end