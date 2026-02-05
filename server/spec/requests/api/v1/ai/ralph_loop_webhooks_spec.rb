# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::RalphLoopWebhooks', type: :request do
  let(:account) { create(:account) }
  let(:webhook_token) { SecureRandom.urlsafe_base64(32) }
  let(:ralph_loop) do
    create(:ai_ralph_loop, :pending, account: account,
           scheduling_mode: 'event_triggered',
           webhook_token: webhook_token)
  end

  # =============================================================================
  # TRIGGER WEBHOOK
  # =============================================================================

  describe 'POST /api/v1/ai/ralph_loops/webhook/:token' do
    context 'with valid webhook token' do
      it 'triggers loop execution for pending loop' do
        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:start_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('triggered_at')
        expect(data).to have_key('loop_id')
        expect(data['loop_id']).to eq(ralph_loop.id)
      end

      it 'resumes a paused loop' do
        ralph_loop.update!(status: 'paused', started_at: 1.hour.ago)

        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:resume_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect_success_response
      end

      it 'runs iteration for a running loop' do
        ralph_loop.update!(status: 'running', started_at: 1.hour.ago)

        service_result = { success: true, iteration: { number: 2 } }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:run_iteration)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect_success_response
      end
    end

    context 'with invalid webhook token' do
      it 'returns unauthorized error' do
        post '/api/v1/ai/ralph_loops/webhook/invalid-token', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'without token' do
      it 'returns not found or routing error' do
        # The route requires a token parameter - missing it would result in routing error
        post '/api/v1/ai/ralph_loops/webhook/', as: :json

        expect(response.status).to be >= 400
      end
    end

    context 'when loop is not event-triggered' do
      let(:manual_loop) do
        create(:ai_ralph_loop, account: account,
               scheduling_mode: 'manual',
               webhook_token: SecureRandom.urlsafe_base64(32))
      end

      it 'returns error' do
        post "/api/v1/ai/ralph_loops/webhook/#{manual_loop.webhook_token}", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when schedule is paused' do
      it 'returns error' do
        ralph_loop.update!(
          schedule_paused: true,
          schedule_paused_at: Time.current,
          schedule_paused_reason: 'Maintenance'
        )

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when loop is in terminal state' do
      it 'returns error for completed loop' do
        ralph_loop.update!(
          status: 'completed',
          started_at: 2.hours.ago,
          completed_at: Time.current
        )

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for failed loop' do
        ralph_loop.update!(
          status: 'failed',
          started_at: 1.hour.ago,
          completed_at: Time.current,
          error_message: 'Test failure'
        )

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for cancelled loop' do
        ralph_loop.update!(
          status: 'cancelled',
          started_at: 1.hour.ago,
          completed_at: Time.current
        )

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when daily limit is exceeded' do
      it 'returns too many requests error' do
        ralph_loop.update!(
          schedule_config: { 'max_iterations_per_day' => 1 },
          daily_iteration_count: 1,
          daily_iteration_reset_at: Date.current
        )

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect(response).to have_http_status(:too_many_requests)
      end
    end

    context 'when execution fails' do
      it 'returns error' do
        service_result = { success: false, error: 'Execution service unavailable' }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:start_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'does not require standard authentication' do
      it 'works without Authorization header' do
        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:start_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}",
             headers: { 'Content-Type' => 'application/json' },
             as: :json

        expect_success_response
      end
    end
  end

  # =============================================================================
  # STATUS ENDPOINT
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops/webhook/:token/status' do
    context 'with valid webhook token' do
      it 'returns loop status' do
        get "/api/v1/ai/ralph_loops/webhook/#{webhook_token}/status", as: :json

        expect_success_response
        data = json_response_data

        expect(data).to include(
          'loop_id' => ralph_loop.id,
          'name' => ralph_loop.name,
          'status' => ralph_loop.status,
          'scheduling_mode' => 'event_triggered'
        )
        expect(data).to have_key('current_iteration')
        expect(data).to have_key('total_tasks')
        expect(data).to have_key('completed_tasks')
        expect(data).to have_key('progress_percentage')
        expect(data).to have_key('daily_iteration_count')
      end
    end

    context 'with invalid webhook token' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/ralph_loops/webhook/invalid-token/status', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when loop is not event-triggered' do
      let(:manual_loop) do
        create(:ai_ralph_loop, account: account,
               scheduling_mode: 'manual',
               webhook_token: SecureRandom.urlsafe_base64(32))
      end

      it 'returns error' do
        get "/api/v1/ai/ralph_loops/webhook/#{manual_loop.webhook_token}/status", as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'does not require standard authentication' do
      it 'works without Authorization header' do
        get "/api/v1/ai/ralph_loops/webhook/#{webhook_token}/status",
            headers: { 'Content-Type' => 'application/json' },
            as: :json

        expect_success_response
      end
    end
  end
end
