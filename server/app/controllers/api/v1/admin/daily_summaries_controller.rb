# frozen_string_literal: true

class Api::V1::Admin::DailySummariesController < ApplicationController
  before_action :ensure_admin_access!

  # GET /api/v1/admin/daily_summaries
  def index
    summaries = Page.where(account: current_user.account)
                    .where("slug LIKE ?", "daily-summary-%")
                    .order(created_at: :desc)

    pagination = pagination_params
    total_count = summaries.count
    summaries = summaries.limit(pagination[:per_page]).offset((pagination[:page] - 1) * pagination[:per_page])

    render_success(
      summaries: summaries.map { |page| serialize_summary(page) },
      meta: {
        current_page: pagination[:page],
        per_page: pagination[:per_page],
        total_count: total_count,
        total_pages: (total_count.to_f / pagination[:per_page]).ceil
      }
    )
  end

  # GET /api/v1/admin/daily_summaries/latest
  def latest
    summary = Page.where(account: current_user.account)
                  .where("slug LIKE ?", "daily-summary-%")
                  .order(created_at: :desc)
                  .first

    if summary
      render_success(summary: serialize_summary(summary, include_content: true))
    else
      render_success(summary: nil)
    end
  end

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
