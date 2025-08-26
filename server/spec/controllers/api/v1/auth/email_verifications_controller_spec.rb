# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Auth::EmailVerificationsController, type: :controller do
  describe '#verify' do
    context 'with valid token' do
      let(:account) { create(:account) }
      let(:user) { create(:user, :unverified, account: account) }
      
      before do
        user.generate_email_verification_token
      end

      it 'verifies the user email successfully' do
        post :verify, params: { token: user.email_verification_token }
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['data']['message']).to eq('Email verified successfully')
        expect(json_response['data']['user']['email_verified']).to be true
        
        user.reload
        expect(user.verified?).to be true
        expect(user.email_verification_token).to be_nil
      end

      it 'creates an audit log entry' do
        expect {
          post :verify, params: { token: user.email_verification_token }
        }.to change(AuditLog, :count).by(1)
        
        audit_log = AuditLog.last
        expect(audit_log.action).to eq('email_verified')
        expect(audit_log.user).to eq(user)
        expect(audit_log.account).to eq(account)
      end
    end

    context 'with invalid token' do
      it 'returns not found error' do
        post :verify, params: { token: 'invalid-token' }
        
        expect(response).to have_http_status(:not_found)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Invalid verification token')
      end
    end

    context 'with expired token' do
      let(:account) { create(:account) }
      let(:user) { create(:user, :unverified, account: account) }
      
      before do
        user.generate_email_verification_token
        # Manually expire the token
        user.update!(email_verification_sent_at: 25.hours.ago)
      end

      it 'returns expired token error' do
        post :verify, params: { token: user.email_verification_token }
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('expired')
      end
    end

    context 'with already verified user' do
      let(:account) { create(:account) }
      let(:user) { create(:user, account: account) }
      
      before do
        user.generate_email_verification_token
      end

      it 'returns already verified message' do
        post :verify, params: { token: user.email_verification_token }
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['data']['message']).to eq('Email is already verified')
      end
    end

    context 'without token parameter' do
      it 'returns bad request error' do
        post :verify
        
        expect(response).to have_http_status(:bad_request)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Verification token is required')
      end
    end
  end

  describe '#resend' do
    let(:account) { create(:account) }
    let(:unverified_user) { create(:user, :unverified, account: account) }
    let(:verified_user) { create(:user, account: account) }

    context 'with authenticated unverified user' do
      before do
        authenticate_as(unverified_user)
        allow(WorkerJobService).to receive(:enqueue_notification_email)
      end

      it 'sends verification email successfully' do
        post :resend
        
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['data']['message']).to eq('Verification email sent successfully')
        
        expect(WorkerJobService).to have_received(:enqueue_notification_email).with(
          'email_verification',
          hash_including(
            user_id: unverified_user.id,
            email: unverified_user.email,
            user_name: unverified_user.full_name
          )
        )
      end

      it 'updates user verification token' do
        expect {
          post :resend
        }.to change { unverified_user.reload.email_verification_token }
        
        expect(unverified_user.email_verification_sent_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'with authenticated verified user' do
      before do
        authenticate_as(verified_user)
      end

      it 'returns already verified error' do
        post :resend
        
        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Email is already verified')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post :resend
        
        expect(response).to have_http_status(:unauthorized)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Access token required')
      end
    end

    context 'with recent resend attempt' do
      before do
        authenticate_as(unverified_user)
        unverified_user.update!(email_verification_sent_at: 2.minutes.ago)
      end

      it 'returns rate limited error with retry information' do
        post :resend
        
        expect(response).to have_http_status(:too_many_requests)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('Please wait')
        expect(json_response['details']['retry_after']).to be > 0
      end
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def authenticate_as(user)
    payload = { user_id: user.id }
    token = JWT.encode(payload, Rails.application.config.jwt_secret_key, 'HS256')
    request.headers['Authorization'] = "Bearer #{token}"
  end
end