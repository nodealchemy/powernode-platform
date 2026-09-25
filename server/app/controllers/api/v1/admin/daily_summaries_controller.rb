# frozen_string_literal: true

class Api::V1::Admin::DailySummariesController < ApplicationController
  before_action :ensure_admin_access!

  # #index and #latest (fc-21) were deleted: the only caller was the admin
  # DailySummariesPage/Panel frontend, which had zero route or importer
  # anywhere and was deleted alongside them. #generate stays — the
  # scheduled DailySummaryJob (worker/app/jobs/daily_summary_job.rb) is
  # still a live caller of it. Confirmed via command grep across core,
  # extensions (public and private) and the worker before deleting.

  # POST /api/v1/admin/daily_summaries/generate
  def generate
    date = params[:date].present? ? Date.parse(params[:date]) : Date.yesterday

    service = DailySummaryService.new(account: current_user.account, date: date)
    page = service.generate!

    render_success(
      summary: serialize_summary(page, include_content: true),
      status: :created
    )
  rescue Date::Error
    render_error("Invalid date format", status: :unprocessable_content)
  end

  private

  def ensure_admin_access!
    unless current_user.has_permission?("admin.access")
      render_error("Access denied", :forbidden)
    end
  end

  def serialize_summary(page, include_content: false)
    data = {
      id: page.id,
      title: page.title,
      slug: page.slug,
      date: page.slug.gsub("daily-summary-", ""),
      published_at: page.published_at,
      word_count: page.word_count,
      estimated_read_time: page.estimated_read_time,
      created_at: page.created_at
    }
    data[:content] = page.content if include_content
    data
  end
end
