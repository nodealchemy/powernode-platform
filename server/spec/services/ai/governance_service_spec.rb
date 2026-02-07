# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::GovernanceService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account) }

  # Stub notification services to avoid external dependencies
  before do
    allow(NotificationService).to receive(:send_all) if defined?(NotificationService)

    if defined?(AiWorkflowOrchestrationChannel)
      unless AiWorkflowOrchestrationChannel.respond_to?(:broadcast_approval_requested)
        AiWorkflowOrchestrationChannel.define_singleton_method(:broadcast_approval_requested) { |*_args| nil }
      end
      allow(AiWorkflowOrchestrationChannel).to receive(:broadcast_approval_requested)
    end
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

    describe '#activate_policy' do
      let(:policy) { create(:ai_compliance_policy, :draft, account: account, created_by: user) }

      it 'activates a draft policy' do
        result = service.activate_policy(policy)

        expect(result[:success]).to be true
        expect(policy.reload.status).to eq('active')
      end
    end

    describe '#evaluate_policies' do
      let!(:blocking_policy) do
        create(:ai_compliance_policy, :active, :blocking,
          account: account,
          created_by: user,
          name: 'Blocking Policy',
          priority: 100,
          conditions: { 'max_tokens' => 1000 })
      end

      let!(:warning_policy) do
        create(:ai_compliance_policy, :active,
          account: account,
          created_by: user,
          name: 'Warning Policy',
          enforcement_level: 'warn',
          priority: 50)
      end

      context 'when all policies allow' do
        before do
          allow_any_instance_of(Ai::CompliancePolicy).to receive(:evaluate).and_return({
            allowed: true,
            reason: 'Within limits',
            enforcement: 'warn'
          })
        end

        it 'returns allowed result' do
          result = service.evaluate_policies({ tokens: 500 })

          expect(result[:allowed]).to be true
          expect(result[:results]).to be_an(Array)
        end
      end

      context 'when a blocking policy denies' do
        before do
          allow_any_instance_of(Ai::CompliancePolicy).to receive(:evaluate) do |policy|
            if policy.enforcement_level == 'block'
              { allowed: false, reason: 'Exceeds token limit', enforcement: 'block' }
            else
              { allowed: true, reason: 'OK', enforcement: 'warn' }
            end
          end

          allow_any_instance_of(Ai::CompliancePolicy).to receive(:blocking?) do |policy|
            policy.enforcement_level == 'block'
          end

          allow_any_instance_of(Ai::CompliancePolicy).to receive(:applies_to?).and_return(true)
        end

        it 'returns blocked result' do
          result = service.evaluate_policies({ tokens: 5000 })

          expect(result[:allowed]).to be false
          blocked_result = result[:results].find { |r| !r[:allowed] }
          expect(blocked_result[:reason]).to include('Exceeds')
        end
      end

      context 'with resource filter' do
        before do
          allow_any_instance_of(Ai::CompliancePolicy).to receive(:applies_to?).and_return(false)
          allow_any_instance_of(Ai::CompliancePolicy).to receive(:evaluate).and_return({
            allowed: true, reason: 'OK', enforcement: 'warn'
          })
        end

        it 'skips policies that do not apply to the resource' do
          result = service.evaluate_policies({ tokens: 500 }, resource: 'agent_execution')
          # All skipped because applies_to? returns false
          expect(result[:allowed]).to be true
          expect(result[:results]).to be_empty
        end
      end
    end
  end

  describe 'Approval Chains' do
    describe '#create_approval_chain' do
      it 'creates an approval chain' do
        chain = service.create_approval_chain(
          name: 'High Cost Approval',
          trigger_type: 'high_cost',
          steps: [
            { 'name' => 'Manager Approval', 'approvers' => [user.id], 'required' => 1 },
            { 'name' => 'Admin Approval', 'approvers' => [user.id], 'required' => 1 }
          ],
          user: user,
          description: 'Required for operations over $100',
          timeout_hours: 24
        )

        expect(chain).to be_persisted
        expect(chain.name).to eq('High Cost Approval')
        expect(chain.trigger_type).to eq('high_cost')
        expect(chain.steps.length).to eq(2)
        expect(chain.status).to eq('active')
        expect(chain.timeout_hours).to eq(24)
      end
    end

    describe '#check_approval_required' do
      let!(:chain) do
        service.create_approval_chain(
          name: 'Deployment Approval',
          trigger_type: 'workflow_deploy',
          steps: [{ 'name' => 'Review', 'approvers' => [user.id] }],
          user: user
        )
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

  describe 'Data Classification' do
    describe '#create_classification' do
      it 'creates a data classification' do
        classification = service.create_classification(
          name: 'PII Detection',
          level: 'confidential',
          detection_patterns: [
            { 'pattern' => '\d{3}-\d{2}-\d{4}', 'type' => 'ssn' },
            { 'pattern' => '\d{4}-\d{4}-\d{4}-\d{4}', 'type' => 'credit_card' }
          ],
          handling_requirements: {
            'mask' => true,
            'log_access' => true,
            'encryption_required' => true
          },
          user: user
        )

        expect(classification).to be_persisted
        expect(classification.name).to eq('PII Detection')
        expect(classification.classification_level).to eq('confidential')
        expect(classification.detection_patterns.length).to eq(2)
      end
    end

    describe '#scan_for_sensitive_data' do
      let!(:classification) do
        service.create_classification(
          name: 'SSN Detector',
          level: 'restricted',
          detection_patterns: [{ 'pattern' => '\d{3}-\d{2}-\d{4}', 'type' => 'ssn' }],
          handling_requirements: { 'mask' => true }
        )
      end

      before do
        allow_any_instance_of(Ai::DataClassification).to receive(:detect_in_text).and_return([])
      end

      it 'scans text and returns detection results' do
        result = service.scan_for_sensitive_data(
          'Clean text without sensitive data',
          source_type: 'message',
          source_id: SecureRandom.uuid
        )

        expect(result).to include(:detections, :has_sensitive_data)
      end

      it 'returns has_sensitive_data false for clean text' do
        result = service.scan_for_sensitive_data(
          'Clean text without sensitive data',
          source_type: 'message',
          source_id: SecureRandom.uuid
        )

        expect(result[:has_sensitive_data]).to be false
      end
    end
  end

  describe 'Compliance Reports' do
    describe '#generate_report' do
      it 'creates a compliance report' do
        report = service.generate_report(
          report_type: 'audit_summary',
          period_start: 30.days.ago,
          period_end: Time.current,
          user: user
        )

        expect(report).to be_persisted
        expect(report.report_type).to eq('audit_summary')
        expect(report.status).to eq('generating')
      end
    end

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
