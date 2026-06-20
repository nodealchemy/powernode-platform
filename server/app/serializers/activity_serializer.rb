# frozen_string_literal: true

# Serializes an activity/audit record for API responses. Extracted from the
# identical inline `activity_json` previously duplicated in
# Api::V1::ActivitiesController and Api::V1::WorkersController.
class ActivitySerializer
  def initialize(activity, options = {})
    @activity = activity
    @options = options
  end

  def as_json
    {
      id: @activity.id,
      action: @activity.activity_type,
      performed_at: @activity.occurred_at.iso8601,
      ip_address: @activity.details["ip_address"],
      user_agent: @activity.details["user_agent"],
      successful: @activity.successful?,
      failed: @activity.failed?,
      duration: @activity.duration,
      response_status: @activity.response_status,
      request_path: @activity.request_path,
      error_message: @activity.error_message,
      details: @activity.details
    }
  end

  def self.serialize(activity, options = {})
    new(activity, options).as_json
  end

  def self.serialize_collection(activities, options = {})
    activities.map { |activity| serialize(activity, options) }
  end
end
