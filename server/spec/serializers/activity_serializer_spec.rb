# frozen_string_literal: true

require 'rails_helper'

# Unit spec for ActivitySerializer, extracted from the identical inline
# `activity_json` previously duplicated in ActivitiesController and
# WorkersController (IMP-9e2234789c5f). Asserts the serialized shape matches the
# activity model's own accessors (i.e. equivalent to the old inline hash).
RSpec.describe ActivitySerializer do
  let(:activity) { create(:worker_activity, :api_request) }

  describe '.serialize' do
    subject(:json) { described_class.serialize(activity) }

    it 'maps the activity to the documented API shape' do
      expect(json).to include(
        id: activity.id,
        action: activity.activity_type,
        performed_at: activity.occurred_at.iso8601,
        ip_address: activity.details["ip_address"],
        user_agent: activity.details["user_agent"],
        successful: activity.successful?,
        failed: activity.failed?,
        duration: activity.duration,
        response_status: activity.response_status,
        request_path: activity.request_path,
        error_message: activity.error_message,
        details: activity.details
      )
    end

    it 'exposes exactly the expected keys (no more, no less)' do
      expect(json.keys).to contain_exactly(
        :id, :action, :performed_at, :ip_address, :user_agent, :successful,
        :failed, :duration, :response_status, :request_path, :error_message, :details
      )
    end
  end

  describe '.serialize_collection' do
    it 'serializes each activity in the collection' do
      activities = create_list(:worker_activity, 2)
      result = described_class.serialize_collection(activities)

      expect(result.size).to eq(2)
      expect(result.map { |h| h[:id] }).to match_array(activities.map(&:id))
    end
  end
end
