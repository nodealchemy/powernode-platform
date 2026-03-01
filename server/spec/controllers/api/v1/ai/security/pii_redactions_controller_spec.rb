# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::Security::PiiRedactionsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:security_user) { create(:user, account: account, permissions: ['ai.security.manage']) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    allow_any_instance_of(Ai::Security::PiiRedactionService).to receive(:scan).and_return({
      detections: [], pii_found: false
    })

    allow_any_instance_of(Ai::Security::PiiRedactionService).to receive(:redact).and_return({
      redacted_text: "safe text", detections_count: 0, types_found: []
    })

    allow_any_instance_of(Ai::Security::PiiRedactionService).to receive(:apply_policy).and_return({
      redacted_text: "safe text", policy_applied: "internal", detections: []
    })

    allow_any_instance_of(Ai::Security::PiiRedactionService).to receive(:safe_to_output?).and_return(true)

    allow_any_instance_of(Ai::Security::PiiRedactionService).to receive(:batch_scan).and_return([])
  end

  describe 'POST #scan' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns scan results' do
        post :scan, params: { content: 'Hello world' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('detections', 'pii_found')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :scan, params: { content: 'test' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #redact' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns redacted text' do
        post :redact, params: { content: 'Call me at 555-123-4567' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('redacted_text', 'detections_count', 'types_found')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :redact, params: { content: 'test' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #apply_policy' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns policy-applied result' do
        post :apply_policy, params: { content: 'test data', policy_name: 'internal' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('redacted_text', 'policy_applied')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :apply_policy, params: { content: 'test', policy_name: 'internal' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #check_output' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns safety check result' do
        post :check_output, params: { content: 'safe text' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('safe')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :check_output, params: { content: 'test' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #batch_scan' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns batch scan results' do
        post :batch_scan, params: { contents: ['text1', 'text2'] }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :batch_scan, params: { contents: ['text'] }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
