# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::GovernanceService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account) }

  # Stub notification services to avoid external dependencies
  before do
    allow(NotificationService).to receive(:send_all) if defined?(NotificationService)
  end

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end
  end

  describe 'Policy Management' do
    describe '#create_policy' do
      it 'creates a compliance policy in draft status' do
        policy = service.create_policy(
          name: 'Data Access Policy',
          policy_type: 'data_access',
          enforcement_level: 'warn',
          user: user,
          description: 'Controls data access for AI operations'
        )

        expect(policy).to be_persisted
        expect(policy.name).to eq('Data Access Policy')
        expect(policy.policy_type).to eq('data_access')
        expect(policy.enforcement_level).to eq('warn')
        expect(policy.status).to eq('draft')
        expect(policy.account).to eq(account)
      end

      it 'creates policy with conditions' do
        policy = service.create_policy(
          name: 'Rate Limit Policy',
          policy_type: 'rate_limit',
          enforcement_level: 'block',
          conditions: {
            'requests_per_minute' => { 'max' => 100 },
            'requests_per_hour' => { 'max' => 1000 }
          }
        )

        expect(policy.conditions['requests_per_minute']).to eq({ 'max' => 100 })
      end

      it 'creates policy with actions' do
        policy = service.create_policy(
          name: 'Cost Limit Policy',
          policy_type: 'cost_limit',
          enforcement_level: 'require_approval',
          actions: {
            'notify' => ['admin'],
            'throttle' => true
          }
        )

        expect(policy.actions['notify']).to eq(['admin'])
      end
    end

  end

  describe 'Approval Chains' do
    describe '#check_approval_required' do
      # #create_approval_chain (the service method) was deleted in fc-12 — it
      # had zero real callers, only this fixture. The chain it built is a
      # plain Ai::ApprovalChain row; the factory replaces it directly.
      let!(:chain) do
        create(:ai_approval_chain, account: account, name: 'Deployment Approval',
               trigger_type: 'workflow_deploy', created_by: user)
      end

      it 'finds matching approval chain' do
        allow_any_instance_of(Ai::ApprovalChain).to receive(:matches_trigger?).and_return(true)

        result = service.check_approval_required(
          trigger_type: 'workflow_deploy',
          context: { environment: 'production' }
        )

        expect(result).to be_present
      end

      it 'returns nil when no chain matches' do
        result = service.check_approval_required(
          trigger_type: 'nonexistent_trigger'
        )

        expect(result).to be_nil
      end
    end
  end

  describe 'Compliance Reports' do
    describe '#get_compliance_summary' do
      it 'returns compliance summary structure' do
        summary = service.get_compliance_summary

        expect(summary).to include(:policies, :violations, :approvals, :data_detections)
        expect(summary[:policies]).to include(:total, :active, :by_type)
      end

      it 'accepts custom date range' do
        summary = service.get_compliance_summary(
          start_date: 7.days.ago,
          end_date: Time.current
        )

        expect(summary[:policies][:total]).to be_a(Integer)
      end
    end
  end

  describe 'Audit Logging' do
    describe '#log_audit_entry' do
      it 'creates an audit log entry' do
        entry = service.log_audit_entry(
          action_type: 'policy_evaluation',
          resource_type: 'Ai::Agent',
          resource_id: SecureRandom.uuid,
          outcome: 'success',
          user: user,
          description: 'Policy evaluation for agent execution',
          context: { execution_id: SecureRandom.uuid }
        )

        expect(entry).to be_persisted
      end

      it 'records before and after states' do
        entry = service.log_audit_entry(
          action_type: 'policy_update',
          resource_type: 'Ai::CompliancePolicy',
          outcome: 'success',
          before_state: { 'enforcement_level' => 'warn' },
          after_state: { 'enforcement_level' => 'block' }
        )

        expect(entry).to be_persisted
      end
    end
  end
end
