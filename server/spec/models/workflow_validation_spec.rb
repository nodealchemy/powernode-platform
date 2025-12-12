# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowValidation, type: :model do
  describe 'associations' do
    it { should belong_to(:workflow).class_name('AiWorkflow').optional }
  end

  describe 'validations' do
    let(:workflow) { create(:ai_workflow) }

    it 'validates overall_status inclusion' do
      validation = build(:workflow_validation, workflow: workflow, overall_status: 'bad_value')
      expect(validation).not_to be_valid
    end

    it 'validates health_score range' do
      validation = build(:workflow_validation, workflow: workflow, health_score: 150)
      expect(validation).not_to be_valid
    end

    it 'validates total_nodes is numeric' do
      validation = WorkflowValidation.new(workflow: workflow, total_nodes: 'invalid', validated_nodes: 0)
      expect(validation).not_to be_valid
    end

    context 'node counts validation' do
      it 'validates validated_nodes cannot exceed total_nodes' do
        validation = build(:workflow_validation, total_nodes: 5, validated_nodes: 10)
        expect(validation).not_to be_valid
        expect(validation.errors[:validated_nodes]).to include('cannot be greater than total nodes')
      end

      it 'allows validated_nodes equal to total_nodes' do
        validation = build(:workflow_validation, total_nodes: 5, validated_nodes: 5)
        expect(validation).to be_valid
      end
    end

    context 'issues format validation' do
      it 'validates issues is an array' do
        validation = build(:workflow_validation, issues: 'invalid')
        expect(validation).not_to be_valid
        expect(validation.errors[:issues]).to include('must be an array')
      end

      it 'validates each issue is a hash' do
        validation = build(:workflow_validation, issues: [ 'invalid', 'items' ])
        expect(validation).not_to be_valid
        expect(validation.errors[:issues]).to include('item at index 0 must be a hash')
      end

      it 'accepts valid issues array' do
        validation = build(:workflow_validation, issues: [
          { code: 'test', severity: 'warning', message: 'Test issue' }
        ])
        expect(validation).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:valid_validation) { create(:workflow_validation, :valid) }
    let!(:invalid_validation) { create(:workflow_validation, :invalid) }
    let!(:warning_validation) { create(:workflow_validation, :with_warnings) }
    let!(:healthy_validation) { create(:workflow_validation, :healthy, health_score: 90) }
    let!(:unhealthy_validation) { create(:workflow_validation, :unhealthy, health_score: 45) }

    describe '.valid' do
      it 'returns only valid validations' do
        expect(WorkflowValidation.valid).to include(valid_validation)
        expect(WorkflowValidation.valid).not_to include(invalid_validation, warning_validation)
      end
    end

    describe '.invalid' do
      it 'returns only invalid validations' do
        expect(WorkflowValidation.invalid).to include(invalid_validation)
        expect(WorkflowValidation.invalid).not_to include(valid_validation)
      end
    end

    describe '.warnings' do
      it 'returns only warning validations' do
        expect(WorkflowValidation.warnings).to include(warning_validation)
        expect(WorkflowValidation.warnings).not_to include(valid_validation, invalid_validation)
      end
    end

    describe '.healthy' do
      it 'returns validations with health score >= 80' do
        expect(WorkflowValidation.healthy).to include(healthy_validation)
        expect(WorkflowValidation.healthy).not_to include(unhealthy_validation)
      end
    end

    describe '.unhealthy' do
      it 'returns validations with health score < 60' do
        expect(WorkflowValidation.unhealthy).to include(unhealthy_validation)
        expect(WorkflowValidation.unhealthy).not_to include(healthy_validation)
      end
    end

    describe '.recent' do
      let!(:old_validation) { create(:workflow_validation, created_at: 2.days.ago) }
      let!(:recent_validation) { create(:workflow_validation, created_at: 1.hour.ago) }

      it 'returns validations from specified time period' do
        results = WorkflowValidation.recent(24.hours)
        expect(results).to include(recent_validation)
        expect(results).not_to include(old_validation)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default values on create' do
        validation = WorkflowValidation.new(
          workflow: create(:ai_workflow),
          total_nodes: 5,
          validated_nodes: 5
        )
        validation.valid?

        expect(validation.issues).to eq([])
        expect(validation.overall_status).to eq('valid')
        expect(validation.health_score).to eq(100)
      end
    end

    describe 'before_save' do
      it 'calculates health score based on issues' do
        validation = create(:workflow_validation, :with_warnings)
        expect(validation.health_score).to be < 100
        expect(validation.health_score).to be > 0
      end

      it 'calculates perfect score for no issues' do
        validation = create(:workflow_validation, :valid, issues: [])
        expect(validation.health_score).to eq(100)
      end
    end
  end

  describe 'status check methods' do
    describe '#validation_valid?' do
      it 'returns true when overall_status is valid' do
        validation = build(:workflow_validation, :valid)
        expect(validation.validation_valid?).to be true
      end

      it 'returns false when overall_status is not valid' do
        validation = build(:workflow_validation, :invalid)
        expect(validation.validation_valid?).to be false
      end
    end

    describe '#validation_invalid?' do
      it 'returns true when overall_status is invalid' do
        validation = build(:workflow_validation, :invalid)
        expect(validation.validation_invalid?).to be true
      end
    end

    describe '#has_warnings?' do
      it 'returns true when overall_status is warning' do
        validation = build(:workflow_validation, :with_warnings)
        expect(validation.has_warnings?).to be true
      end
    end
  end

  describe 'issue queries' do
    let(:validation) { create(:workflow_validation, :with_warnings) }

    describe '#error_issues' do
      it 'returns only error severity issues' do
        errors = validation.error_issues
        expect(errors).to be_empty  # with_warnings trait has no errors
      end
    end

    describe '#warning_issues' do
      it 'returns only warning severity issues' do
        warnings = validation.warning_issues
        expect(warnings.size).to be > 0
        expect(warnings.all? { |i| i['severity'] == 'warning' }).to be true
      end
    end

    describe '#error_count' do
      it 'counts error issues' do
        validation = create(:workflow_validation, :invalid)
        expect(validation.error_count).to be > 0
      end
    end

    describe '#warning_count' do
      it 'counts warning issues' do
        expect(validation.warning_count).to be > 0
      end
    end
  end

  describe '#stale?' do
    it 'returns true for old validations' do
      validation = create(:workflow_validation, created_at: 2.hours.ago)
      expect(validation.stale?(1.hour)).to be true
    end

    it 'returns false for recent validations' do
      validation = create(:workflow_validation, created_at: 30.minutes.ago)
      expect(validation.stale?(1.hour)).to be false
    end
  end

  describe '#issues_by_category' do
    let(:validation) { create(:workflow_validation, :with_warnings) }

    it 'filters issues by category' do
      connectivity_issues = validation.issues_by_category('connectivity')
      expect(connectivity_issues.size).to be > 0
      expect(connectivity_issues.all? { |i| i['category'] == 'connectivity' }).to be true
    end
  end

  describe '#has_issue?' do
    let(:validation) { create(:workflow_validation, :with_warnings) }

    it 'checks for specific issue codes' do
      expect(validation.has_issue?('orphaned_node')).to be true
      expect(validation.has_issue?('nonexistent_issue')).to be false
    end
  end

  describe '#auto_fixable_issues' do
    let(:validation) { create(:workflow_validation, :auto_fixable_issues) }

    it 'returns only auto-fixable issues' do
      fixable = validation.auto_fixable_issues
      expect(fixable.size).to be > 0
      expect(fixable.all? { |i| i['auto_fixable'] == true }).to be true
    end
  end

  describe '#summary' do
    let(:validation) { create(:workflow_validation, :with_warnings) }

    it 'returns validation summary' do
      summary = validation.summary

      expect(summary).to include(:workflow_id, :overall_status, :health_score)
      expect(summary[:issues]).to include(:errors, :warnings, :info, :total)
      expect(summary[:issues][:total]).to eq(validation.issues.size)
    end
  end
end
