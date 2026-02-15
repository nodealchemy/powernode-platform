# frozen_string_literal: true

module Api
  module V1
    module Marketing
      class ContentCalendarController < ApplicationController
        before_action :set_entry, only: %i[update destroy]

        # GET /api/v1/marketing/calendar
        def index
          authorize_read!

          service = ::Marketing::ContentCalendarService.new(current_user.account)
          entries = service.list(filter_params)

          render_success(items: entries.map(&:calendar_summary))
        end

        # POST /api/v1/marketing/calendar
        def create
          authorize_manage!

          service = ::Marketing::ContentCalendarService.new(current_user.account)
          entry = service.create(calendar_params)

          render_success({ entry: entry.calendar_summary }, status: :created)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages, status: :unprocessable_content)
        rescue ::Marketing::ContentCalendarService::CalendarError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH/PUT /api/v1/marketing/calendar/:id
        def update
          authorize_manage!

          service = ::Marketing::ContentCalendarService.new(current_user.account)
          entry = service.update(@entry, calendar_params)

          render_success(entry: entry.calendar_summary)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages, status: :unprocessable_content)
        end

        # DELETE /api/v1/marketing/calendar/:id
        def destroy
          authorize_manage!

          @entry.destroy!
          render_success(message: "Calendar entry deleted successfully")
        end

        # GET /api/v1/marketing/calendar/conflicts
        def conflicts
          authorize_read!

          service = ::Marketing::ContentCalendarService.new(current_user.account)
          result = service.detect_conflicts(
            date: params[:date],
            time: params[:time],
            entry_type: params[:entry_type],
            exclude_id: params[:exclude_id]
          )

          render_success(conflicts: result)
        end

        private

        def set_entry
          @entry = current_user.account.marketing_content_calendars.find(params[:id])
        end

        def calendar_params
          params.require(:calendar).permit(
            :title, :entry_type, :scheduled_date, :scheduled_time,
            :all_day, :color, :status, :campaign_id, :description,
            metadata: {}
          )
        end

        def filter_params
          params.permit(:start_date, :end_date, :entry_type, :status, :campaign_id).to_h
        end

        def authorize_read!
          return if current_user.has_permission?("marketing.calendar.read")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_manage!
          return if current_user.has_permission?("marketing.calendar.manage")

          render_error("Insufficient permissions", status: :forbidden)
        end
      end
    end
  end
end
