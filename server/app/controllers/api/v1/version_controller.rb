# frozen_string_literal: true

class Api::V1::VersionController < ApplicationController
  skip_before_action :authenticate_request, only: [ :show, :health ]

  # GET /api/v1/version
  def show
    render_success(Powernode::Version.semantic_version)
  end

  # GET /api/v1/version/full
  def full
    render_success(Powernode::Version.full_version_info)
  end

  # GET /api/v1/version/health
  def health
    render_success({
      status: "healthy",
      version: Powernode::Version.current,
      timestamp: Time.current.iso8601,
      uptime: uptime_info
    })
  end

  private

  def uptime_info
    boot_time = Rails.application.config.boot_time || Time.current
    uptime_seconds = Time.current - boot_time

    {
      boot_time: boot_time.iso8601,
      uptime_seconds: uptime_seconds.to_i,
      uptime_human: humanize_duration(uptime_seconds)
    }
  end

  def humanize_duration(seconds)
    days = seconds / 86400
    hours = (seconds % 86400) / 3600
    minutes = (seconds % 3600) / 60
    seconds = seconds % 60

    parts = []
    parts << "#{days.to_i}d" if days >= 1
    parts << "#{hours.to_i}h" if hours >= 1
    parts << "#{minutes.to_i}m" if minutes >= 1
    parts << "#{seconds.to_i}s" if parts.empty? || seconds >= 1

    parts.join(" ")
  end
end
