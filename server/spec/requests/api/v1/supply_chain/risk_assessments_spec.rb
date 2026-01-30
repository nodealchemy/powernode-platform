# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::RiskAssessments', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write']) }
  let(:admin_user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write', 'supply_chain.admin']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['supply_chain.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:unauthorized_headers) { auth_headers_for(unauthorized_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  let(:vendor) { create(:supply_chain_vendor, account: account) }
  let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

  describe 'GET /api/v1/supply_chain/vendors/:vendor_id/assessments' do
    let!(:assessment1) do
      create(:supply_chain_risk_assessment, :with_assessor,
             account: account,
             vendor: vendor,
             status: 'draft',
             assessment_type: 'initial')
    end
    let!(:assessment2) do
      create(:supply_chain_risk_assessment, :with_assessor,
             account: account,
             vendor: vendor,
             status: 'completed',
             assessment_type: 'periodic')
    end

    context 'with proper permissions' do
      it 'returns list of risk assessments for vendor' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['risk_assessments']).to be_an(Array)
        expect(data['risk_assessments'].length).to eq(2)
        expect(json_response['meta']).to have_key('total_count')
      end

      it 'filters by status' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
            params: { status: 'draft' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['risk_assessments'].length).to eq(1)
        expect(data['risk_assessments'].first['status']).to eq('draft')
      end

      it 'filters by assessment type' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
            params: { type: 'periodic' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['risk_assessments'].all? { |a| a['assessment_type'] == 'periodic' }).to be true
      end

      it 'returns not found for non-existent vendor' do
        get "/api/v1/supply_chain/vendors/#{SecureRandom.uuid}/assessments", headers: headers, as: :json

        expect_error_response('Vendor not found', 404)
      end
    end

    context 'accessing vendor from different account' do
      it 'returns not found error' do
        get "/api/v1/supply_chain/vendors/#{other_vendor.id}/assessments", headers: headers, as: :json

        expect_error_response('Vendor not found', 404)
      end
    end

    context 'without supply_chain.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments", headers: unauthorized_headers, as: :json

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/vendors/:vendor_id/assessments/:id' do
    let(:assessment) do
      create(:supply_chain_risk_assessment, :with_assessor, :with_findings, :with_recommendations, :with_evidence,
             account: account,
             vendor: vendor)
    end

    context 'with proper permissions' do
      it 'returns risk assessment details' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['risk_assessment']['id']).to eq(assessment.id)
        expect(data['risk_assessment']['assessment_type']).to eq(assessment.assessment_type)
        expect(data['risk_assessment']['status']).to eq(assessment.status)
        expect(data['risk_assessment']['risk_level']).to eq(assessment.risk_level)
        expect(data['risk_assessment']['assessor']).to be_present
        # Details included in show
        expect(data['risk_assessment']['findings']).to be_present
        expect(data['risk_assessment']['recommendations']).to be_present
        expect(data['risk_assessment']['evidence']).to be_present
      end

      it 'returns not found for non-existent assessment' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{SecureRandom.uuid}",
            headers: headers,
            as: :json

        expect_error_response('Risk assessment not found', 404)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/vendors/:vendor_id/assessments' do
    let(:valid_params) do
      {
        risk_assessment: {
          assessment_type: 'initial',
          assessment_date: Date.current,
          security_score: 85,
          compliance_score: 90,
          operational_score: 88,
          valid_until: 1.year.from_now.to_date,
          findings: ['Strong security posture', 'Good compliance framework'],
          recommendations: ['Continue monitoring', 'Review annually'],
          evidence: ['SOC2 Report']
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new risk assessment' do
        expect {
          post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change { vendor.risk_assessments.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['risk_assessment']['assessment_type']).to eq('initial')
        expect(data['risk_assessment']['status']).to eq('draft')
        expect(data['risk_assessment']['security_score'].to_f).to eq(85)
        expect(data['risk_assessment']['compliance_score'].to_f).to eq(90)

        assessment = vendor.risk_assessments.last
        expect(assessment.assessor).to eq(user)
        expect(assessment.account).to eq(account)
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(risk_assessment: { assessment_type: nil })

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
             params: invalid_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
             params: valid_params,
             headers: read_only_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/submit_for_review' do
    let(:assessment) do
      create(:supply_chain_risk_assessment, :with_assessor,
             account: account,
             vendor: vendor,
             status: 'draft')
    end

    context 'with admin permissions' do
      it 'submits the assessment for review' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/submit_for_review",
             headers: admin_headers,
             as: :json

        expect_success_response
      end

      it 'returns error when assessment cannot be submitted' do
        assessment.update!(status: 'completed')

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/submit_for_review",
             headers: admin_headers,
             as: :json

        expect_error_response('Assessment cannot be submitted for review in current status', 422)
      end
    end

    context 'without supply_chain.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/submit_for_review",
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions for supply chain administration', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/complete' do
    let(:assessment) do
      create(:supply_chain_risk_assessment, :with_assessor, :pending_review,
             account: account,
             vendor: vendor)
    end

    context 'with admin permissions' do
      it 'completes the risk assessment' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/complete",
             params: { valid_months: 12 },
             headers: admin_headers,
             as: :json

        expect_success_response
      end

      it 'returns error when assessment is not pending review' do
        assessment.update!(status: 'draft')

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/complete",
             headers: admin_headers,
             as: :json

        expect_error_response('Assessment is not pending review', 422)
      end
    end

    context 'without supply_chain.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/complete",
             params: { valid_months: 12 },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions for supply chain administration', 403)
      end
    end
  end
end
