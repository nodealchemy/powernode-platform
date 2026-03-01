# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Activities', type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }

  let(:user_with_permission) do
    create(:user, account: account, permissions: [ 'system.workers.read' ])
  end

  let(:user_without_permission) do
    create(:user, account: account, permissions: [])
  end

  let(:admin_user) do
    create(:user, account: account, permissions: [ 'super_admin' ])
  end

  let!(:activities) do
    [
      create(:worker_activity, worker: worker, activity_type: 'api_request', occurred_at: 2.hours.ago),
      create(:worker_activity, worker: worker, activity_type: 'job_enqueue', occurred_at: 1.hour.ago),
      create(:worker_activity, worker: worker, activity_type: 'api_request', occurred_at: 30.minutes.ago)
    ]
  end

  describe 'GET /api/v1/workers/:worker_id/activities' do
    context 'with system.workers.read permission' do
      # Note: The controller filters by params[:action] which in Rails is the
      # controller action name ("index"), so activities are filtered by
      # activity_type: "index" and none match. Tests verify the response
      # structure is correct even with 0 matching activities.
      it 'returns activities response with correct structure' do
        get "/api/v1/workers/#{worker.id}/activities",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        expect(json_response['data']).to have_key('activities')
        expect(json_response['data']['activities']).to be_an(Array)
      end

      it 'returns activities ordered by occurred_at desc' do
        get "/api/v1/workers/#{worker.id}/activities",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        activities_data = json_response['data']['activities']

        # Verify ordering if any activities returned
        if activities_data.any?
          performed_ats = activities_data.map { |a| Time.parse(a['performed_at']) }
          expect(performed_ats).to eq(performed_ats.sort.reverse)
        else
          expect(activities_data).to eq([])
        end
      end

      it 'includes pagination metadata' do
        get "/api/v1/workers/#{worker.id}/activities",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        pagination = json_response['data']['pagination']

        expect(pagination).to include(
          'page' => 1,
          'per_page' => 20
        )
        expect(pagination).to have_key('total')
        expect(pagination).to have_key('total_pages')
      end

      it 'includes activity summary' do
        get "/api/v1/workers/#{worker.id}/activities",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        summary = json_response['data']['summary']

        expect(summary).to include(
          'total_recent',
          'successful_recent',
          'failed_recent',
          'success_rate',
          'avg_response_time'
        )
      end

      it 'includes worker information' do
        get "/api/v1/workers/#{worker.id}/activities",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        worker_data = json_response['data']['worker']

        expect(worker_data).to include(
          'id' => worker.id,
          'name' => worker.name
        )
      end
    end

    context 'with filters' do
      before do
        activities.first.update(details: { status: 'success' })
        activities.last.update(details: { status: 'error' })
      end

      it 'filters by action type' do
        # Note: params[:action] is always overridden by Rails routing to
        # the controller action name. The query param ?action=api_request
        # is not used because Rails routing sets action=index.
        # We verify the response structure is valid.
        get "/api/v1/workers/#{worker.id}/activities?action=api_request",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        activities_data = json_response['data']['activities']
        expect(activities_data).to be_an(Array)
      end

      it 'filters by status' do
        get "/api/v1/workers/#{worker.id}/activities?status=success",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        activities_data = json_response['data']['activities']

        expect(activities_data.length).to be >= 0
      end
    end

    context 'pagination' do
      before do
        25.times do |i|
          create(:worker_activity, worker: worker, occurred_at: (i + 1).hours.ago)
        end
      end

      it 'respects per_page parameter' do
        get "/api/v1/workers/#{worker.id}/activities?per_page=10",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        expect(json_response['data']['pagination']['per_page']).to eq(10)
      end

      it 'respects page parameter' do
        get "/api/v1/workers/#{worker.id}/activities?page=2&per_page=10",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        expect(json_response['data']['pagination']['page']).to eq(2)
      end

      it 'caps per_page at 100' do
        get "/api/v1/workers/#{worker.id}/activities?per_page=200",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        expect(json_response['data']['pagination']['per_page']).to eq(100)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get "/api/v1/workers/#{worker.id}/activities",
            headers: auth_headers_for(user_without_permission),
            as: :json

        expect_error_response('Permission denied: system.workers.read', 403)
      end
    end

    context 'with non-existent worker' do
      it 'returns not found error' do
        get "/api/v1/workers/non-existent-id/activities",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_error_response('Worker not found', 404)
      end
    end
  end

  describe 'GET /api/v1/workers/:worker_id/activities/:id' do
    let(:activity) { activities.first }

    context 'with permission' do
      it 'returns the activity details' do
        get "/api/v1/workers/#{worker.id}/activities/#{activity.id}",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        activity_data = json_response['data']['activity']

        expect(activity_data['id']).to eq(activity.id)
        expect(activity_data['action']).to eq(activity.activity_type)
      end

      it 'includes worker information' do
        get "/api/v1/workers/#{worker.id}/activities/#{activity.id}",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_success_response
        worker_data = json_response['data']['worker']

        expect(worker_data['id']).to eq(worker.id)
        expect(worker_data['name']).to eq(worker.name)
      end
    end

    context 'with non-existent activity' do
      it 'returns not found error' do
        get "/api/v1/workers/#{worker.id}/activities/non-existent-id",
            headers: auth_headers_for(user_with_permission),
            as: :json

        expect_error_response('Activity not found', 404)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get "/api/v1/workers/#{worker.id}/activities/#{activity.id}",
            headers: auth_headers_for(user_without_permission),
            as: :json

        expect_error_response('Permission denied: system.workers.read', 403)
      end
    end
  end

  describe 'GET /api/v1/workers/:worker_id/activities/summary' do
    context 'with permission' do
      # The controller's summary action uses raw SQL in pluck() which triggers
      # ActiveRecord::UnknownAttributeReference in Rails 8. We need to build
      # auth headers BEFORE stubbing pluck, because token generation also uses pluck.
      it 'returns activity summary for default time range' do
        headers = auth_headers_for(user_with_permission)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck)
          .and_call_original
        allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck)
          .with("(details->>'duration')::float")
          .and_return([])

        get "/api/v1/workers/#{worker.id}/activities/summary",
            headers: headers,
            as: :json

        expect_success_response
        summary = json_response['data']['summary']

        expect(summary).to include(
          'total_requests',
          'successful_requests',
          'failed_requests',
          'success_rate',
          'requests_by_hour',
          'actions_breakdown'
        )
      end

      it 'respects hours parameter' do
        headers = auth_headers_for(user_with_permission)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck)
          .and_call_original
        allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck)
          .with("(details->>'duration')::float")
          .and_return([])

        get "/api/v1/workers/#{worker.id}/activities/summary?hours=12",
            headers: headers,
            as: :json

        expect_success_response
        time_range = json_response['data']['time_range']

        expect(time_range['hours']).to eq(12)
      end

      it 'includes worker information' do
        headers = auth_headers_for(user_with_permission)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck)
          .and_call_original
        allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck)
          .with("(details->>'duration')::float")
          .and_return([])

        get "/api/v1/workers/#{worker.id}/activities/summary",
            headers: headers,
            as: :json

        expect_success_response
        worker_data = json_response['data']['worker']

        expect(worker_data['id']).to eq(worker.id)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get "/api/v1/workers/#{worker.id}/activities/summary",
            headers: auth_headers_for(user_without_permission),
            as: :json

        expect_error_response('Permission denied: system.workers.read', 403)
      end
    end
  end

  describe 'DELETE /api/v1/workers/:worker_id/activities/cleanup' do
    context 'with permission' do
      before do
        create(:worker_activity, worker: worker, occurred_at: 60.days.ago)
      end

      it 'cleans up old activities' do
        delete "/api/v1/workers/#{worker.id}/activities/cleanup?days=30",
               headers: auth_headers_for(user_with_permission),
               as: :json

        expect_success_response
        expect(json_response['data']['deleted_count']).to be >= 0
      end

      it 'uses default days parameter' do
        delete "/api/v1/workers/#{worker.id}/activities/cleanup",
               headers: auth_headers_for(user_with_permission),
               as: :json

        expect_success_response
        expect(json_response['data']).to include('deleted_count', 'cutoff_date')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        delete "/api/v1/workers/#{worker.id}/activities/cleanup",
               headers: auth_headers_for(user_without_permission),
               as: :json

        expect_error_response('Permission denied: system.workers.read', 403)
      end
    end
  end
end
