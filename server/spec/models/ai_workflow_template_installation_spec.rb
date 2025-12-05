# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowTemplateInstallation, type: :model do
  subject(:installation) { build(:ai_workflow_template_installation) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow_template) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_workflow).class_name('AiWorkflow').optional }
    it { is_expected.to belong_to(:installer).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:ai_workflow_template) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:status) }
    
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending installing completed failed cancelled]) }

    context 'uniqueness validation' do
      it 'validates unique installation per template per account' do
        existing = create(:ai_workflow_template_installation)
        duplicate = build(:ai_workflow_template_installation,
                         ai_workflow_template: existing.ai_workflow_template,
                         account: existing.account)
        
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:ai_workflow_template]).to include('has already been installed for this account')
      end

      it 'allows same template in different accounts' do
        template = create(:ai_workflow_template)
        account1 = create(:account)
        account2 = create(:account)
        
        create(:ai_workflow_template_installation, ai_workflow_template: template, account: account1)
        duplicate = build(:ai_workflow_template_installation, ai_workflow_template: template, account: account2)
        
        expect(duplicate).to be_valid
      end
    end

    context 'rating validation' do
      it 'validates rating is within valid range' do
        installation = build(:ai_workflow_template_installation, rating: 6)
        expect(installation).not_to be_valid
        expect(installation.errors[:rating]).to include('must be between 1 and 5')
      end

      it 'allows nil rating' do
        installation = build(:ai_workflow_template_installation, rating: nil)
        expect(installation).to be_valid
      end

      it 'accepts valid ratings' do
        (1..5).each do |rating|
          installation = build(:ai_workflow_template_installation, rating: rating)
          expect(installation).to be_valid, "Expected rating #{rating} to be valid"
        end
      end
    end

    context 'customization validation' do
      it 'validates customization is a hash when present' do
        installation = build(:ai_workflow_template_installation, customization: 'not a hash')
        expect(installation).not_to be_valid
        expect(installation.errors[:customization]).to include('must be a hash')
      end

      it 'allows nil customization' do
        installation = build(:ai_workflow_template_installation, customization: nil)
        expect(installation).to be_valid
      end

      it 'validates customization size limits' do
        large_customization = { data: 'x' * 100_000 }
        installation = build(:ai_workflow_template_installation, customization: large_customization)
        
        expect(installation).not_to be_valid
        expect(installation.errors[:customization]).to include('exceeds maximum size limit')
      end
    end

    context 'completed installation validation' do
      it 'requires created_workflow for completed installations' do
        installation = build(:ai_workflow_template_installation, 
                            status: 'completed',
                            created_workflow: nil)
        
        expect(installation).not_to be_valid
        expect(installation.errors[:created_workflow]).to include("can't be blank for completed installations")
      end

      it 'allows nil created_workflow for non-completed statuses' do
        %w[pending installing failed cancelled].each do |status|
          installation = build(:ai_workflow_template_installation, 
                              status: status,
                              created_workflow: nil)
          expect(installation).to be_valid, "Expected status '#{status}' to be valid without created_workflow"
        end
      end
    end

    context 'failed installation validation' do
      it 'requires error_message for failed installations' do
        installation = build(:ai_workflow_template_installation,
                            status: 'failed',
                            error_message: nil)
        
        expect(installation).not_to be_valid
        expect(installation.errors[:error_message]).to include("can't be blank for failed installations")
      end

      it 'validates error_message length' do
        installation = build(:ai_workflow_template_installation,
                            status: 'failed',
                            error_message: 'x' * 2001)
        
        expect(installation).not_to be_valid
        expect(installation.errors[:error_message]).to include('is too long (maximum is 2000 characters)')
      end
    end
  end

  describe 'scopes' do
    let!(:pending_installation) { create(:ai_workflow_template_installation, status: 'pending') }
    let!(:installing_installation) { create(:ai_workflow_template_installation, status: 'installing') }
    let!(:completed_installation) { create(:ai_workflow_template_installation, status: 'completed') }
    let!(:failed_installation) { create(:ai_workflow_template_installation, status: 'failed') }
    let!(:recent_installation) { create(:ai_workflow_template_installation, created_at: 1.hour.ago) }
    let!(:old_installation) { create(:ai_workflow_template_installation, created_at: 1.month.ago) }

    describe '.by_status' do
      it 'filters installations by status' do
        expect(described_class.by_status('completed')).to include(completed_installation)
        expect(described_class.by_status('completed')).not_to include(pending_installation)
      end
    end

    describe '.pending' do
      it 'returns pending installations' do
        expect(described_class.pending).to include(pending_installation)
        expect(described_class.pending).not_to include(completed_installation)
      end
    end

    describe '.active' do
      it 'returns pending and installing installations' do
        active_installations = described_class.active
        expect(active_installations).to include(pending_installation, installing_installation)
        expect(active_installations).not_to include(completed_installation, failed_installation)
      end
    end

    describe '.completed' do
      it 'returns completed installations' do
        expect(described_class.completed).to include(completed_installation)
        expect(described_class.completed).not_to include(pending_installation)
      end
    end

    describe '.failed' do
      it 'returns failed installations' do
        expect(described_class.failed).to include(failed_installation)
        expect(described_class.failed).not_to include(completed_installation)
      end
    end

    describe '.recent' do
      it 'returns installations from last 24 hours by default' do
        expect(described_class.recent).to include(recent_installation)
        expect(described_class.recent).not_to include(old_installation)
      end

      it 'accepts custom time range' do
        expect(described_class.recent(2.months)).to include(recent_installation, old_installation)
      end
    end

    describe '.for_template' do
      let(:template1) { create(:ai_workflow_template) }
      let(:template2) { create(:ai_workflow_template) }
      let!(:installation1) { create(:ai_workflow_template_installation, ai_workflow_template: template1) }
      let!(:installation2) { create(:ai_workflow_template_installation, ai_workflow_template: template2) }

      it 'filters installations by template' do
        expect(described_class.for_template(template1)).to include(installation1)
        expect(described_class.for_template(template1)).not_to include(installation2)
      end
    end

    describe '.for_account' do
      let(:account1) { create(:account) }
      let(:account2) { create(:account) }
      let!(:installation1) { create(:ai_workflow_template_installation, account: account1) }
      let!(:installation2) { create(:ai_workflow_template_installation, account: account2) }

      it 'filters installations by account' do
        expect(described_class.for_account(account1)).to include(installation1)
        expect(described_class.for_account(account1)).not_to include(installation2)
      end
    end

    describe '.rated' do
      let!(:rated_installation) { create(:ai_workflow_template_installation, rating: 4) }
      let!(:unrated_installation) { create(:ai_workflow_template_installation, rating: nil) }

      it 'returns installations with ratings' do
        expect(described_class.rated).to include(rated_installation)
        expect(described_class.rated).not_to include(unrated_installation)
      end
    end

    describe '.with_feedback' do
      let!(:feedback_installation) { create(:ai_workflow_template_installation, feedback: 'Great template!') }
      let!(:no_feedback_installation) { create(:ai_workflow_template_installation, feedback: nil) }

      it 'returns installations with feedback' do
        expect(described_class.with_feedback).to include(feedback_installation)
        expect(described_class.with_feedback).not_to include(no_feedback_installation)
      end
    end
  end

  describe 'state machine and callbacks' do
    describe 'status transitions' do
      it 'starts in pending status' do
        installation = create(:ai_workflow_template_installation)
        expect(installation.status).to eq('pending')
      end

      it 'can transition from pending to installing' do
        installation = create(:ai_workflow_template_installation, status: 'pending')
        installation.start_installation!
        
        expect(installation.status).to eq('installing')
        expect(installation.started_at).to be_present
      end

      it 'can transition from installing to completed' do
        workflow = create(:ai_workflow)
        installation = create(:ai_workflow_template_installation, status: 'installing')
        installation.mark_completed!(workflow)
        
        expect(installation.status).to eq('completed')
        expect(installation.completed_at).to be_present
        expect(installation.created_workflow).to eq(workflow)
      end

      it 'can transition from installing to failed' do
        installation = create(:ai_workflow_template_installation, status: 'installing')
        installation.mark_failed!('Template validation failed')
        
        expect(installation.status).to eq('failed')
        expect(installation.completed_at).to be_present
        expect(installation.error_message).to eq('Template validation failed')
      end

      it 'can cancel pending or installing installations' do
        pending_installation = create(:ai_workflow_template_installation, status: 'pending')
        installing_installation = create(:ai_workflow_template_installation, status: 'installing')
        
        pending_installation.cancel!
        installing_installation.cancel!
        
        expect(pending_installation.status).to eq('cancelled')
        expect(installing_installation.status).to eq('cancelled')
      end

      it 'prevents invalid transitions' do
        completed_installation = create(:ai_workflow_template_installation, status: 'completed')
        
        expect {
          completed_installation.start_installation!
        }.to raise_error(StandardError, /invalid transition/i)
      end
    end

    describe 'callbacks' do
      describe 'before_validation' do
        it 'generates installation_identifier if not present' do
          installation = build(:ai_workflow_template_installation, installation_identifier: nil)
          installation.valid?
          
          expect(installation.installation_identifier).to be_present
          expect(installation.installation_identifier).to match(/^[A-Z0-9]{12}$/)
        end

        it 'preserves provided installation_identifier' do
          installation = build(:ai_workflow_template_installation, installation_identifier: 'CUSTOM12345')
          installation.valid?
          expect(installation.installation_identifier).to eq('CUSTOM12345')
        end
      end

      describe 'after_create' do
        it 'triggers installation workflow' do
          expect_any_instance_of(described_class).to receive(:trigger_installation_workflow)
          create(:ai_workflow_template_installation)
        end

        it 'sends installation notification' do
          expect_any_instance_of(described_class).to receive(:send_installation_notification)
          create(:ai_workflow_template_installation)
        end
      end

      describe 'after_update' do
        it 'logs status changes' do
          installation = create(:ai_workflow_template_installation, status: 'pending')
          
          expect {
            installation.start_installation!
          }.to change { AiWorkflowExecutionLog.count }.by(1)
          
          log = AiWorkflowExecutionLog.last
          expect(log.message).to include('Installation status changed from pending to installing')
        end

        it 'updates template installation statistics' do
          template = create(:ai_workflow_template)
          installation = create(:ai_workflow_template_installation, ai_workflow_template: template)
          
          expect {
            installation.mark_completed!(create(:ai_workflow))
          }.to change { template.reload.installation_count }.by(1)
        end

        it 'triggers completion notifications' do
          installation = create(:ai_workflow_template_installation, status: 'installing')
          
          expect(installation).to receive(:send_completion_notification)
          installation.mark_completed!(create(:ai_workflow))
        end
      end
    end
  end

  describe 'instance methods' do
    describe '#duration' do
      it 'returns nil when not started' do
        installation = create(:ai_workflow_template_installation, started_at: nil)
        expect(installation.duration).to be_nil
      end

      it 'returns duration from start to completion' do
        installation = create(:ai_workflow_template_installation,
                              started_at: 1.hour.ago,
                              completed_at: 30.minutes.ago)
        expect(installation.duration).to eq(30.minutes)
      end

      it 'returns duration from start to now for active installations' do
        installation = create(:ai_workflow_template_installation, status: 'installing', started_at: 1.hour.ago)
        expect(installation.duration).to be_within(1.second).of(1.hour)
      end
    end

    describe '#success?' do
      it 'returns true for completed installations' do
        installation = create(:ai_workflow_template_installation, status: 'completed')
        expect(installation.success?).to be true
      end

      it 'returns false for other statuses' do
        %w[pending installing failed cancelled].each do |status|
          installation = create(:ai_workflow_template_installation, status: status)
          expect(installation.success?).to be false
        end
      end
    end

    describe '#failed?' do
      it 'returns true for failed installations' do
        installation = create(:ai_workflow_template_installation, status: 'failed')
        expect(installation.failed?).to be true
      end

      it 'returns false for other statuses' do
        %w[pending installing completed cancelled].each do |status|
          installation = create(:ai_workflow_template_installation, status: status)
          expect(installation.failed?).to be false
        end
      end
    end

    describe '#can_be_cancelled?' do
      it 'returns true for pending and installing installations' do
        expect(create(:ai_workflow_template_installation, status: 'pending').can_be_cancelled?).to be true
        expect(create(:ai_workflow_template_installation, status: 'installing').can_be_cancelled?).to be true
      end

      it 'returns false for completed, failed, and cancelled installations' do
        %w[completed failed cancelled].each do |status|
          installation = create(:ai_workflow_template_installation, status: status)
          expect(installation.can_be_cancelled?).to be false
        end
      end
    end

    describe '#can_be_retried?' do
      it 'returns true for failed installations within retry limit' do
        installation = create(:ai_workflow_template_installation, status: 'failed', retry_count: 2)
        expect(installation.can_be_retried?).to be true
      end

      it 'returns false for installations that exceeded retry limit' do
        installation = create(:ai_workflow_template_installation, status: 'failed', retry_count: 5)
        expect(installation.can_be_retried?).to be false
      end

      it 'returns false for non-failed installations' do
        installation = create(:ai_workflow_template_installation, status: 'completed')
        expect(installation.can_be_retried?).to be false
      end
    end

    describe '#retry_installation!' do
      it 'creates new installation with incremented retry count' do
        failed_installation = create(:ai_workflow_template_installation, status: 'failed', retry_count: 1)
        
        expect {
          new_installation = failed_installation.retry_installation!
          expect(new_installation.retry_count).to eq(2)
          expect(new_installation.status).to eq('pending')
          expect(new_installation.parent_installation_id).to eq(failed_installation.id)
        }.to change { described_class.count }.by(1)
      end

      it 'raises error when retry limit exceeded' do
        failed_installation = create(:ai_workflow_template_installation, status: 'failed', retry_count: 5)
        
        expect {
          failed_installation.retry_installation!
        }.to raise_error(StandardError, /retry limit exceeded/i)
      end
    end

    describe '#apply_customizations' do
      let(:template) { create(:ai_workflow_template, :content_generation) }
      let(:installation) { create(:ai_workflow_template_installation, ai_workflow_template: template) }

      it 'applies variable customizations to workflow creation' do
        customizations = {
          workflow_name: 'My Custom Blog Generator',
          variables: {
            topic: 'AI Technology',
            word_count: 1200,
            style: 'technical'
          }
        }
        
        installation.customization = customizations
        result = installation.apply_customizations(template.configuration)
        
        expect(result[:workflow_name]).to eq('My Custom Blog Generator')
        expect(result[:input_variables]['topic']).to eq('AI Technology')
        expect(result[:input_variables]['word_count']).to eq(1200)
      end

      it 'validates customization against template schema' do
        invalid_customizations = {
          variables: {
            invalid_variable: 'value'
          }
        }
        
        installation.customization = invalid_customizations
        
        expect {
          installation.apply_customizations(template.configuration)
        }.to raise_error(StandardError, /invalid variable/i)
      end

      it 'applies node configuration overrides' do
        customizations = {
          node_overrides: {
            'content_generator' => {
              configuration: {
                temperature: 0.9,
                max_tokens: 2000
              }
            }
          }
        }
        
        installation.customization = customizations
        result = installation.apply_customizations(template.configuration)
        
        content_node = result[:nodes].find { |n| n[:id] == 'content_generator' }
        expect(content_node[:configuration][:temperature]).to eq(0.9)
        expect(content_node[:configuration][:max_tokens]).to eq(2000)
      end
    end

    describe '#installation_summary' do
      let(:installation) { create(:ai_workflow_template_installation, :enterprise,
                                  started_at: 1.hour.ago,
                                  completed_at: 30.minutes.ago,
                                  rating: 4,
                                  feedback: 'Great template!') }

      it 'returns comprehensive installation information' do
        summary = installation.installation_summary
        
        expect(summary).to include(
          :installation_id,
          :template_name,
          :status,
          :duration_seconds,
          :success,
          :rating,
          :feedback,
          :customization_applied,
          :created_workflow_id
        )
        
        expect(summary[:duration_seconds]).to eq(1800) # 30 minutes
        expect(summary[:success]).to be true
        expect(summary[:rating]).to eq(4)
      end
    end

    describe '#generate_completion_report' do
      let(:workflow) { create(:ai_workflow) }
      let(:installation) { create(:ai_workflow_template_installation, status: 'completed', created_workflow: workflow) }

      it 'generates detailed completion report' do
        report = installation.generate_completion_report
        
        expect(report).to include(
          :installation_details,
          :workflow_created,
          :customizations_applied,
          :installation_metrics,
          :next_steps
        )
        
        expect(report[:workflow_created][:id]).to eq(workflow.id)
        expect(report[:installation_metrics][:duration]).to be_present
      end

      it 'includes customization analysis in report' do
        installation.customization = { variables: { custom_var: 'value' } }
        report = installation.generate_completion_report
        
        expect(report[:customizations_applied]).to be_present
        expect(report[:customization_impact]).to be_present
      end
    end

    describe '#uninstall!' do
      let(:workflow) { create(:ai_workflow) }
      let(:installation) { create(:ai_workflow_template_installation, status: 'completed', created_workflow: workflow) }

      it 'marks installation as uninstalled and optionally removes workflow' do
        expect {
          installation.uninstall!(remove_workflow: true)
        }.to change { AiWorkflow.count }.by(-1)
        
        expect(installation.reload.status).to eq('uninstalled')
        expect(installation.uninstalled_at).to be_present
      end

      it 'preserves workflow when configured' do
        expect {
          installation.uninstall!(remove_workflow: false)
        }.not_to change { AiWorkflow.count }
        
        expect(installation.reload.status).to eq('uninstalled')
        expect(workflow.reload.template_id).to be_nil # Disconnects from template
      end

      it 'creates uninstallation log entry' do
        expect {
          installation.uninstall!
        }.to change { AiWorkflowExecutionLog.count }.by(1)
        
        log = AiWorkflowExecutionLog.last
        expect(log.message).to include('Template uninstalled')
      end
    end

    describe '#rate_and_review!' do
      let(:installation) { create(:ai_workflow_template_installation, status: 'completed') }

      it 'adds rating and feedback to installation' do
        installation.rate_and_review!(rating: 5, feedback: 'Excellent template!')
        
        expect(installation.rating).to eq(5)
        expect(installation.feedback).to eq('Excellent template!')
        expect(installation.reviewed_at).to be_within(1.second).of(Time.current)
      end

      it 'validates rating constraints' do
        expect {
          installation.rate_and_review!(rating: 6, feedback: 'Invalid rating')
        }.to raise_error(StandardError, /rating must be between 1 and 5/i)
      end

      it 'allows updating existing ratings' do
        installation.update!(rating: 3, feedback: 'Okay template')
        
        installation.rate_and_review!(rating: 5, feedback: 'Actually great!')
        
        expect(installation.rating).to eq(5)
        expect(installation.feedback).to eq('Actually great!')
      end
    end
  end

  describe 'class methods' do
    describe '.install_template_for_account' do
      let(:template) { create(:ai_workflow_template, :published) }
      let(:account) { create(:account) }

      it 'creates installation and triggers workflow creation' do
        customizations = {
          workflow_name: 'Custom Workflow',
          variables: { topic: 'Test Topic' }
        }
        
        expect {
          installation = described_class.install_template_for_account(template, account, customizations)
          expect(installation.status).to eq('pending')
          expect(installation.customization).to eq(customizations)
        }.to change { described_class.count }.by(1)
      end

      it 'prevents duplicate installations' do
        create(:ai_workflow_template_installation, ai_workflow_template: template, account: account)
        
        expect {
          described_class.install_template_for_account(template, account)
        }.to raise_error(StandardError, /already installed/i)
      end

      it 'validates template availability' do
        unpublished_template = create(:ai_workflow_template, is_published: false)
        
        expect {
          described_class.install_template_for_account(unpublished_template, account)
        }.to raise_error(StandardError, /not available for installation/i)
      end
    end

    describe '.process_pending_installations' do
      let!(:pending_installations) { create_list(:ai_workflow_template_installation, 3, status: 'pending') }

      it 'processes all pending installations' do
        expect {
          result = described_class.process_pending_installations
          expect(result[:processed]).to eq(3)
          expect(result[:successful]).to be >= 0
          expect(result[:failed]).to be >= 0
        }.to change { described_class.where(status: 'pending').count }.by(-3)
      end

      it 'handles processing failures gracefully' do
        allow_any_instance_of(AiWorkflowTemplate).to receive(:create_workflow_from_template)
          .and_raise(StandardError, 'Processing failed')
        
        result = described_class.process_pending_installations
        expect(result[:failed]).to eq(3)
        expect(described_class.where(status: 'failed').count).to eq(3)
      end
    end

    describe '.installation_statistics' do
      before do
        template = create(:ai_workflow_template)
        create_list(:ai_workflow_template_installation, 5, :completed, ai_workflow_template: template)
        create_list(:ai_workflow_template_installation, 2, :failed, ai_workflow_template: template)
        create_list(:ai_workflow_template_installation, 1, :pending, ai_workflow_template: template)
      end

      it 'calculates installation success metrics' do
        stats = described_class.installation_statistics
        
        expect(stats[:total_installations]).to eq(8)
        expect(stats[:successful_installations]).to eq(5)
        expect(stats[:failed_installations]).to eq(2)
        expect(stats[:success_rate]).to eq(0.625) # 5/8
      end

      it 'includes timing and performance metrics' do
        stats = described_class.installation_statistics(include_performance: true)
        
        expect(stats[:average_installation_time]).to be_present
        expect(stats[:installation_trends]).to be_present
      end
    end

    describe '.popular_templates' do
      before do
        template1 = create(:ai_workflow_template)
        template2 = create(:ai_workflow_template)
        template3 = create(:ai_workflow_template)
        
        create_list(:ai_workflow_template_installation, 10, :completed, ai_workflow_template: template1)
        create_list(:ai_workflow_template_installation, 5, :completed, ai_workflow_template: template2)
        create_list(:ai_workflow_template_installation, 2, :completed, ai_workflow_template: template3)
      end

      it 'returns templates ordered by installation count' do
        popular = described_class.popular_templates(limit: 3)
        
        expect(popular.first.installation_count).to eq(10)
        expect(popular.second.installation_count).to eq(5)
        expect(popular.third.installation_count).to eq(2)
      end

      it 'can filter by time period' do
        create(:ai_workflow_template_installation, :completed, created_at: 2.days.ago)
        
        recent_popular = described_class.popular_templates(since: 1.day.ago)
        expect(recent_popular.count).to be >= 3
      end
    end

    describe '.cleanup_old_installations' do
      before do
        create_list(:ai_workflow_template_installation, 3, :failed, created_at: 2.months.ago)
        create_list(:ai_workflow_template_installation, 2, :cancelled, created_at: 1.month.ago)
        create_list(:ai_workflow_template_installation, 1, :completed, created_at: 1.week.ago)
      end

      it 'removes old failed and cancelled installations' do
        expect {
          described_class.cleanup_old_installations(30.days)
        }.to change { described_class.count }.by(-5)
        
        # Should preserve completed installations
        expect(described_class.completed.count).to eq(1)
      end

      it 'preserves installations with associated workflows' do
        workflow = create(:ai_workflow)
        old_completed = create(:ai_workflow_template_installation, 
                              :completed, 
                              created_at: 2.months.ago,
                              created_workflow: workflow)
        
        described_class.cleanup_old_installations(30.days)
        expect(described_class.exists?(old_completed.id)).to be true
      end
    end
  end

  describe 'performance and edge cases' do
    describe 'concurrent installation handling' do
      it 'prevents race conditions during simultaneous installations' do
        template = create(:ai_workflow_template, :published)
        account = create(:account)
        
        # Simulate concurrent installation attempts
        threads = 3.times.map do
          Thread.new do
            begin
              described_class.install_template_for_account(template, account)
            rescue StandardError
              # Expected - only one should succeed
            end
          end
        end
        
        threads.each(&:join)
        
        # Should only have one installation
        expect(described_class.where(ai_workflow_template: template, account: account).count).to eq(1)
      end
    end

    describe 'large customization data handling' do
      it 'handles complex customization structures efficiently' do
        large_customization = {
          variables: Hash[100.times.map { |i| ["var_#{i}", "value_#{i}"] }],
          node_overrides: Hash[20.times.map { |i| 
            ["node_#{i}", { configuration: { setting: "value_#{i}" } }]
          }],
          workflow_metadata: {
            description: 'Custom workflow ' * 100,
            tags: Array.new(50) { |i| "tag_#{i}" }
          }
        }
        
        installation = build(:ai_workflow_template_installation, customization: large_customization)
        expect(installation).to be_valid
        expect(installation.save!).to be true
      end
    end

    describe 'unicode and special character handling' do
      it 'handles unicode in installation data' do
        unicode_installation = create(:ai_workflow_template_installation,
                                     feedback: 'Excellent template! 优秀的模板 🚀',
                                     customization: {
                                       workflow_name: '智能工作流 AI Workflow',
                                       variables: {
                                         title: 'Título con acentos',
                                         description: 'Description with émojis 🎉'
                                       }
                                     })
        
        expect(unicode_installation).to be_valid
        expect(unicode_installation.feedback).to include('🚀')
        expect(unicode_installation.reload.customization['workflow_name']).to eq('智能工作流 AI Workflow')
      end
    end

    describe 'query performance with large datasets' do
      before do
        create_list(:ai_workflow_template_installation, 1000, :completed)
        create_list(:ai_workflow_template_installation, 500, :failed)
      end

      it 'efficiently queries installation statistics' do
        expect {
          described_class.installation_statistics
          described_class.popular_templates(limit: 10)
        }.not_to exceed_query_limit(5)
      end

      it 'efficiently filters and orders large result sets' do
        expect {
          described_class.completed
                        .recent(30.days)
                        .includes(:ai_workflow_template, :account)
                        .order(completed_at: :desc)
                        .limit(50)
                        .to_a
        }.not_to exceed_query_limit(3)
      end
    end

    describe 'error handling and recovery' do
      it 'handles template deletion during installation' do
        template = create(:ai_workflow_template)
        installation = create(:ai_workflow_template_installation, 
                             ai_workflow_template: template,
                             status: 'installing')
        
        template.destroy
        
        # Installation should still be accessible for cleanup
        expect(installation.reload.ai_workflow_template_id).to be_present
        expect { installation.mark_failed!('Template no longer available') }.not_to raise_error
      end

      it 'handles account deletion gracefully' do
        account = create(:account)
        installation = create(:ai_workflow_template_installation, account: account)
        
        account.destroy
        
        # Installation should be cleaned up
        expect(described_class.exists?(installation.id)).to be false
      end
    end

    describe 'installation workflow orchestration' do
      it 'coordinates complex multi-step installation process' do
        template = create(:ai_workflow_template, :content_generation)
        account = create(:account)
        
        installation = described_class.install_template_for_account(template, account, {
          workflow_name: 'Test Blog Generator',
          variables: { topic: 'Technology' }
        })
        
        # Simulate installation processing
        installation.start_installation!
        expect(installation.status).to eq('installing')
        
        # Simulate successful workflow creation
        workflow = create(:ai_workflow, account: account, name: 'Test Blog Generator')
        installation.mark_completed!(workflow)
        
        expect(installation.success?).to be true
        expect(installation.created_workflow).to eq(workflow)
      end
    end
  end
end