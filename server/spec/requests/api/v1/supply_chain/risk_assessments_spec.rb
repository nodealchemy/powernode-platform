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
      create(:supply_chain_risk_assessment,
             account: account,
             vendor: vendor,
             assessed_by: user,
             status: 'pending',
             assessment_type: 'initial')
    end
    let!(:assessment2) do
      create(:supply_chain_risk_assessment,
             account: account,
             vendor: vendor,
             assessed_by: user,
             status: 'approved',
             assessment_type: 'annual')
    end

    context 'with proper permissions' do
      it 'returns list of risk assessments for vendor' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['risk_assessments']).to be_an(Array)
        expect(data['risk_assessments'].length).to eq(2)
        expect(data['meta']).to have_key('total')
      end

      it 'filters by status' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
            params: { status: 'pending' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['risk_assessments'].length).to eq(1)
        expect(data['risk_assessments'].first['status']).to eq('pending')
      end

      it 'filters by assessment type' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
            params: { type: 'annual' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['risk_assessments'].all? { |a| a['assessment_type'] == 'annual' }).to be true
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
      create(:supply_chain_risk_assessment,
             account: account,
             vendor: vendor,
             assessed_by: user,
             approved_by: admin_user,
             findings: ['Finding 1', 'Finding 2'],
             recommendations: ['Rec 1', 'Rec 2'],
             controls_evaluated: ['Control 1'])
    end

    context 'with proper permissions' do
      it 'returns risk assessment details' do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['risk_assessment']).to include(
          'id' => assessment.id,
          'assessment_type' => assessment.assessment_type,
          'status' => assessment.status,
          'overall_risk_level' => assessment.overall_risk_level
        )
        expect(data['risk_assessment']['assessed_by']).to be_present
        expect(data['risk_assessment']['findings']).to be_present
        expect(data['risk_assessment']['recommendations']).to be_present
        expect(data['risk_assessment']['controls_evaluated']).to be_present
        expect(data['risk_assessment']['approved_by']).to be_present
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
          financial_score: 92,
          reputation_score: 87,
          overall_risk_level: 'low',
          notes: 'Comprehensive assessment completed',
          valid_until: 1.year.from_now.to_date,
          findings: ['Strong security posture', 'Good compliance framework'],
          recommendations: ['Continue monitoring', 'Review annually'],
          controls_evaluated: ['ISO 27001', 'SOC 2']
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new risk assessment' do
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:calculate_scores!)
        allow(SupplyChainChannel).to receive(:broadcast_vendor_assessment_completed)

        expect {
          post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change { vendor.risk_assessments.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['risk_assessment']).to include(
          'assessment_type' => 'initial',
          'status' => 'pending',
          'security_score' => 85,
          'compliance_score' => 90
        )

        assessment = vendor.risk_assessments.last
        expect(assessment.assessed_by).to eq(user)
        expect(assessment.account).to eq(account)
        expect(SupplyChainChannel).to have_received(:broadcast_vendor_assessment_completed).with(assessment)
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

  describe 'POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/approve' do
    let(:assessment) do
      create(:supply_chain_risk_assessment,
             account: account,
             vendor: vendor,
             assessed_by: user,
             status: 'pending')
    end

    context 'with admin permissions' do
      it 'approves the risk assessment' do
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:pending?).and_return(true)
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:approve!)
        allow_any_instance_of(SupplyChain::Vendor).to receive(:update_risk_profile_from_assessment)

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/approve",
             params: { comment: 'Assessment looks good' },
             headers: admin_headers,
             as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Risk assessment approved')
        expect(vendor).to have_received(:update_risk_profile_from_assessment).with(assessment)
      end

      it 'returns error when assessment is not pending' do
        assessment.update!(status: 'approved')
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:pending?).and_return(false)

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/approve",
             headers: admin_headers,
             as: :json

        expect_error_response('Assessment is not pending approval', 422)
      end
    end

    context 'without supply_chain.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/approve",
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions for supply chain administration', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/vendors/:vendor_id/assessments/:id/reject' do
    let(:assessment) do
      create(:supply_chain_risk_assessment,
             account: account,
             vendor: vendor,
             assessed_by: user,
             status: 'pending')
    end

    context 'with admin permissions' do
      it 'rejects the risk assessment' do
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:pending?).and_return(true)
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:reject!)

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/reject",
             params: { reason: 'Incomplete documentation' },
             headers: admin_headers,
             as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Risk assessment rejected')
      end

      it 'returns error when assessment is not pending' do
        assessment.update!(status: 'approved')
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:pending?).and_return(false)

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/reject",
             params: { reason: 'Test' },
             headers: admin_headers,
             as: :json

        expect_error_response('Assessment is not pending approval', 422)
      end

      it 'returns error when reason is missing' do
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:pending?).and_return(true)

        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/reject",
             headers: admin_headers,
             as: :json

        expect_error_response('Rejection reason is required', 422)
      end
    end

    context 'without supply_chain.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assessments/#{assessment.id}/reject",
             params: { reason: 'Test' },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions for supply chain administration', 403)
      end
    end
  end
end
