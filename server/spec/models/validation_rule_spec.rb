# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ValidationRule, type: :model do
  describe 'validations' do
    subject { build(:validation_rule) }

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:category) }

    it 'validates category inclusion' do
      rule = build(:validation_rule, category: 'invalid')
      expect(rule).not_to be_valid
      expect(rule.errors[:category]).to include('must be a valid category')
    end

    it 'validates severity has default value' do
      rule = ValidationRule.new(name: 'test', category: 'structure')
      rule.valid?
      expect(rule.severity).to eq('warning')
    end

    it 'validates severity inclusion' do
      rule = build(:validation_rule, severity: 'invalid')
      expect(rule).not_to be_valid
      expect(rule.errors[:severity]).to include('must be error, warning, or info')
    end

    context 'configuration validation' do
      it 'validates configuration is a hash' do
        rule = build(:validation_rule, configuration: 'invalid')
        expect(rule).not_to be_valid
        expect(rule.errors[:configuration]).to include('must be a hash')
      end

      it 'accepts valid configuration hash' do
        rule = build(:validation_rule, configuration: { check_interval: 300 })
        expect(rule).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:enabled_rule) { create(:validation_rule, enabled: true) }
    let!(:disabled_rule) { create(:validation_rule, :disabled) }
    let!(:auto_fixable_rule) { create(:validation_rule, :auto_fixable) }
    let!(:error_rule) { create(:validation_rule, :error_severity) }
    let!(:warning_rule) { create(:validation_rule, :warning_severity) }

    describe '.enabled' do
      it 'returns only enabled rules' do
        expect(ValidationRule.enabled).to include(enabled_rule)
        expect(ValidationRule.enabled).not_to include(disabled_rule)
      end
    end

    describe '.disabled' do
      it 'returns only disabled rules' do
        expect(ValidationRule.disabled).to include(disabled_rule)
        expect(ValidationRule.disabled).not_to include(enabled_rule)
      end
    end

    describe '.auto_fixable' do
      it 'returns only auto-fixable rules' do
        expect(ValidationRule.auto_fixable).to include(auto_fixable_rule)
        expect(ValidationRule.auto_fixable).not_to include(enabled_rule)
      end
    end

    describe '.by_category' do
      let!(:structure_rule) { create(:validation_rule, :structure_validation) }
      let!(:security_rule) { create(:validation_rule, :security_validation) }

      it 'filters by category' do
        expect(ValidationRule.by_category('structure')).to include(structure_rule)
        expect(ValidationRule.by_category('structure')).not_to include(security_rule)
      end
    end

    describe '.by_severity' do
      it 'filters by severity' do
        expect(ValidationRule.by_severity('error')).to include(error_rule)
        expect(ValidationRule.by_severity('error')).not_to include(warning_rule)
      end
    end

    describe '.errors' do
      it 'returns only error severity rules' do
        expect(ValidationRule.errors).to include(error_rule)
        expect(ValidationRule.errors).not_to include(warning_rule)
      end
    end

    describe '.warnings' do
      it 'returns only warning severity rules' do
        expect(ValidationRule.warnings).to include(warning_rule)
        expect(ValidationRule.warnings).not_to include(error_rule)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default values on create' do
        rule = ValidationRule.new(name: 'test_rule', category: 'structure')
        rule.valid?

        expect(rule.enabled).to be true
        expect(rule.auto_fixable).to be false
        expect(rule.severity).to eq('warning')
        expect(rule.configuration).to eq({})
      end
    end
  end

  describe 'severity check methods' do
    describe '#error?' do
      it 'returns true when severity is error' do
        rule = build(:validation_rule, :error_severity)
        expect(rule.error?).to be true
      end

      it 'returns false when severity is not error' do
        rule = build(:validation_rule, :warning_severity)
        expect(rule.error?).to be false
      end
    end

    describe '#warning?' do
      it 'returns true when severity is warning' do
        rule = build(:validation_rule, :warning_severity)
        expect(rule.warning?).to be true
      end
    end

    describe '#info?' do
      it 'returns true when severity is info' do
        rule = build(:validation_rule, :info_severity)
        expect(rule.info?).to be true
      end
    end
  end

  describe '#enable!' do
    it 'enables the rule' do
      rule = create(:validation_rule, :disabled)
      rule.enable!
      expect(rule.reload.enabled).to be true
    end
  end

  describe '#disable!' do
    it 'disables the rule' do
      rule = create(:validation_rule, enabled: true)
      rule.disable!
      expect(rule.reload.enabled).to be false
    end
  end

  describe '#config_value' do
    it 'retrieves configuration values' do
      rule = create(:validation_rule, configuration: { check_interval: 300, threshold: 80 })
      expect(rule.config_value('check_interval')).to eq(300)
      expect(rule.config_value('threshold')).to eq(80)
    end

    it 'returns nil for missing keys' do
      rule = create(:validation_rule, configuration: {})
      expect(rule.config_value('missing_key')).to be_nil
    end
  end

  describe '#has_capability?' do
    it 'checks for specific capabilities' do
      rule = create(:validation_rule, configuration: {
        'capabilities' => { 'auto_fix' => true, 'validate' => true }
      })

      expect(rule.has_capability?('auto_fix')).to be true
      expect(rule.has_capability?('validate')).to be true
      expect(rule.has_capability?('missing')).to be_falsey
    end
  end
end
