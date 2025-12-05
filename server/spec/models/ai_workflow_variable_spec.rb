# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowVariable, type: :model do
  subject(:variable) { build(:ai_workflow_variable) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:ai_workflow) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:variable_type) }
    
    it { is_expected.to validate_inclusion_of(:variable_type).in_array(%w[string number integer boolean array object json text url email password date datetime file enum]) }

    context 'name validation' do
      it 'validates name format' do
        valid_names = ['user_id', 'apiKey', 'maxRetries', 'endpoint_url', 'API_TOKEN']
        invalid_names = ['123invalid', 'user-name', 'user name', 'user@email', 'user.name']

        valid_names.each do |name|
          variable = build(:ai_workflow_variable, name: name)
          expect(variable).to be_valid, "Expected '#{name}' to be valid"
        end

        invalid_names.each do |name|
          variable = build(:ai_workflow_variable, name: name)
          expect(variable).not_to be_valid, "Expected '#{name}' to be invalid"
          expect(variable.errors[:name]).to be_present
        end
      end

      it 'validates name uniqueness within workflow' do
        workflow = create(:ai_workflow)
        create(:ai_workflow_variable, ai_workflow: workflow, name: 'duplicate_name')
        
        duplicate = build(:ai_workflow_variable, ai_workflow: workflow, name: 'duplicate_name')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different workflows' do
        workflow1 = create(:ai_workflow)
        workflow2 = create(:ai_workflow)
        
        create(:ai_workflow_variable, ai_workflow: workflow1, name: 'same_name')
        duplicate = build(:ai_workflow_variable, ai_workflow: workflow2, name: 'same_name')
        
        expect(duplicate).to be_valid
      end
    end

    context 'default_value validation' do
      it 'validates default_value type matches variable_type' do
        # String type
        variable = build(:ai_workflow_variable, :string_type, default_value: 123)
        expect(variable).not_to be_valid
        expect(variable.errors[:default_value]).to include('must be a string')

        # Number type
        variable = build(:ai_workflow_variable, :number_type, default_value: 'not_a_number')
        expect(variable).not_to be_valid
        expect(variable.errors[:default_value]).to include('must be a number')

        # Boolean type
        variable = build(:ai_workflow_variable, :boolean_type, default_value: 'true')
        expect(variable).not_to be_valid
        expect(variable.errors[:default_value]).to include('must be a boolean')

        # Array type
        variable = build(:ai_workflow_variable, :array_type, default_value: 'not_an_array')
        expect(variable).not_to be_valid
        expect(variable.errors[:default_value]).to include('must be an array')
      end

      it 'allows nil default_value for optional variables' do
        variable = build(:ai_workflow_variable, is_required: false, default_value: nil)
        expect(variable).to be_valid
      end

      it 'requires default_value for required variables unless explicitly nil' do
        variable = build(:ai_workflow_variable, :required, default_value: nil)
        expect(variable).to be_valid # Required variables can have nil default if user must provide
      end
    end

    context 'validation_rules validation' do
      it 'validates string type rules' do
        invalid_rules = { min_length: -1, max_length: 'invalid' }
        variable = build(:ai_workflow_variable, :string_type, validation_rules: invalid_rules)
        
        expect(variable).not_to be_valid
        expect(variable.errors[:validation_rules]).to include('min_length must be non-negative')
        expect(variable.errors[:validation_rules]).to include('max_length must be a positive integer')
      end

      it 'validates number type rules' do
        invalid_rules = { min: 'invalid', max: -100 }
        variable = build(:ai_workflow_variable, :number_type, validation_rules: invalid_rules)
        
        expect(variable).not_to be_valid
        expect(variable.errors[:validation_rules]).to include('min must be a number')
      end

      it 'validates array type rules' do
        invalid_rules = { min_items: -1, max_items: 'invalid', item_type: 'invalid_type' }
        variable = build(:ai_workflow_variable, :array_type, validation_rules: invalid_rules)
        
        expect(variable).not_to be_valid
        expect(variable.errors[:validation_rules]).to include('min_items must be non-negative')
        expect(variable.errors[:validation_rules]).to include('max_items must be a positive integer')
        expect(variable.errors[:validation_rules]).to include('item_type must be a valid type')
      end

      it 'validates enum type rules' do
        invalid_rules = { allowed_values: 'not_an_array' }
        variable = build(:ai_workflow_variable, :enum_type, validation_rules: invalid_rules)
        
        expect(variable).not_to be_valid
        expect(variable.errors[:validation_rules]).to include('allowed_values must be an array')
      end

      it 'accepts valid validation rules' do
        valid_rules = {
          min_length: 1,
          max_length: 255,
          pattern: '^[a-zA-Z0-9_]+$'
        }
        variable = build(:ai_workflow_variable, :string_type, validation_rules: valid_rules)
        expect(variable).to be_valid
      end
    end

    context 'sensitive variable validation' do
      it 'requires encryption for sensitive variables' do
        variable = build(:ai_workflow_variable, :sensitive, is_sensitive: true)
        expect(variable.metadata['encryption_required']).to be true
      end

      it 'prevents default values for sensitive variables' do
        variable = build(:ai_workflow_variable, :password_type, 
                        is_sensitive: true, 
                        default_value: 'secret_password')
        
        expect(variable).not_to be_valid
        expect(variable.errors[:default_value]).to include('cannot be set for sensitive variables')
      end
    end
  end

  describe 'scopes' do
    let!(:required_var) { create(:ai_workflow_variable, :required) }
    let!(:optional_var) { create(:ai_workflow_variable, is_required: false) }
    let!(:sensitive_var) { create(:ai_workflow_variable, :sensitive) }
    let!(:string_var) { create(:ai_workflow_variable, :string_type) }
    let!(:number_var) { create(:ai_workflow_variable, :number_type) }

    describe '.required' do
      it 'returns only required variables' do
        expect(described_class.required).to include(required_var)
        expect(described_class.required).not_to include(optional_var)
      end
    end

    describe '.optional' do
      it 'returns only optional variables' do
        expect(described_class.optional).to include(optional_var)
        expect(described_class.optional).not_to include(required_var)
      end
    end

    describe '.sensitive' do
      it 'returns only sensitive variables' do
        expect(described_class.sensitive).to include(sensitive_var)
        expect(described_class.sensitive).not_to include(string_var)
      end
    end

    describe '.by_type' do
      it 'filters variables by type' do
        expect(described_class.by_type('string')).to include(string_var)
        expect(described_class.by_type('string')).not_to include(number_var)
      end
    end

    describe '.for_workflow' do
      let(:workflow1) { create(:ai_workflow) }
      let(:workflow2) { create(:ai_workflow) }
      let!(:var1) { create(:ai_workflow_variable, ai_workflow: workflow1) }
      let!(:var2) { create(:ai_workflow_variable, ai_workflow: workflow2) }

      it 'filters variables by workflow' do
        expect(described_class.for_workflow(workflow1)).to include(var1)
        expect(described_class.for_workflow(workflow1)).not_to include(var2)
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_validation' do
      it 'normalizes variable_type' do
        variable = build(:ai_workflow_variable, variable_type: '  STRING  ')
        variable.valid?
        expect(variable.variable_type).to eq('string')
      end

      it 'strips whitespace from name' do
        variable = build(:ai_workflow_variable, name: '  variable_name  ')
        variable.valid?
        expect(variable.name).to eq('variable_name')
      end

      it 'sets metadata defaults for sensitive variables' do
        variable = build(:ai_workflow_variable, is_sensitive: true, metadata: nil)
        variable.valid?
        
        expect(variable.metadata['encryption_required']).to be true
        expect(variable.metadata['masked_in_logs']).to be true
      end
    end

    describe 'after_save' do
      it 'invalidates workflow cache when variable changes' do
        workflow = create(:ai_workflow)
        variable = create(:ai_workflow_variable, ai_workflow: workflow)
        
        expect(workflow).to receive(:invalidate_variables_cache)
        variable.update!(description: 'Updated description')
      end
    end
  end

  describe 'instance methods' do
    describe '#validate_value' do
      context 'string validation' do
        let(:variable) { create(:ai_workflow_variable, :string_type) }

        it 'validates string length constraints' do
          variable.validation_rules = { min_length: 5, max_length: 10 }
          
          expect(variable.validate_value('test')).to be false
          expect(variable.validate_value('valid_test')).to be true
          expect(variable.validate_value('this_is_too_long')).to be false
        end

        it 'validates pattern matching' do
          variable.validation_rules = { pattern: '^[A-Z]{2,3}-\\d{4,6}$' }
          
          expect(variable.validate_value('AB-1234')).to be true
          expect(variable.validate_value('ABC-123456')).to be true
          expect(variable.validate_value('invalid-format')).to be false
        end

        it 'returns validation errors' do
          variable.validation_rules = { min_length: 5 }
          variable.validate_value('bad')
          
          expect(variable.last_validation_errors).to include('too short')
        end
      end

      context 'number validation' do
        let(:variable) { create(:ai_workflow_variable, :number_type) }

        it 'validates numeric ranges' do
          variable.validation_rules = { min: 0, max: 100 }
          
          expect(variable.validate_value(-1)).to be false
          expect(variable.validate_value(50)).to be true
          expect(variable.validate_value(101)).to be false
        end

        it 'validates integer constraints' do
          variable.validation_rules = { integer_only: true }
          
          expect(variable.validate_value(42)).to be true
          expect(variable.validate_value(42.5)).to be false
        end
      end

      context 'array validation' do
        let(:variable) { create(:ai_workflow_variable, :array_type) }

        it 'validates array size constraints' do
          variable.validation_rules = { min_items: 2, max_items: 5 }
          
          expect(variable.validate_value(['single'])).to be false
          expect(variable.validate_value(['two', 'items'])).to be true
          expect(variable.validate_value(['too', 'many', 'items', 'here', 'now', 'six'])).to be false
        end

        it 'validates item types' do
          variable.validation_rules = { item_type: 'string' }
          
          expect(variable.validate_value(['all', 'strings'])).to be true
          expect(variable.validate_value(['mixed', 123, 'types'])).to be false
        end

        it 'validates unique items constraint' do
          variable.validation_rules = { unique_items: true }
          
          expect(variable.validate_value(['unique', 'items'])).to be true
          expect(variable.validate_value(['duplicate', 'duplicate'])).to be false
        end
      end

      context 'object validation' do
        let(:variable) { create(:ai_workflow_variable, :object_type) }

        it 'validates required properties' do
          variable.validation_rules = {
            required_properties: ['name', 'value'],
            properties: {
              name: { type: 'string' },
              value: { type: 'number' }
            }
          }
          
          valid_object = { name: 'test', value: 42 }
          invalid_object = { name: 'test' } # missing 'value'
          
          expect(variable.validate_value(valid_object)).to be true
          expect(variable.validate_value(invalid_object)).to be false
        end

        it 'validates property types' do
          variable.validation_rules = {
            properties: {
              count: { type: 'integer', min: 0 },
              active: { type: 'boolean' }
            }
          }
          
          valid_object = { count: 5, active: true }
          invalid_object = { count: -1, active: 'not_boolean' }
          
          expect(variable.validate_value(valid_object)).to be true
          expect(variable.validate_value(invalid_object)).to be false
        end
      end

      context 'enum validation' do
        let(:variable) { create(:ai_workflow_variable, :enum_type) }

        it 'validates allowed values' do
          variable.validation_rules = { allowed_values: ['small', 'medium', 'large'] }
          
          expect(variable.validate_value('medium')).to be true
          expect(variable.validate_value('extra_large')).to be false
        end

        it 'respects case sensitivity settings' do
          variable.validation_rules = { 
            allowed_values: ['Small', 'Medium', 'Large'],
            case_sensitive: false
          }
          
          expect(variable.validate_value('small')).to be true
          expect(variable.validate_value('MEDIUM')).to be true
          
          variable.validation_rules[:case_sensitive] = true
          expect(variable.validate_value('small')).to be false
          expect(variable.validate_value('Small')).to be true
        end
      end

      context 'special type validation' do
        it 'validates email format' do
          variable = create(:ai_workflow_variable, :email_type)
          
          expect(variable.validate_value('valid@example.com')).to be true
          expect(variable.validate_value('invalid-email')).to be false
        end

        it 'validates URL format' do
          variable = create(:ai_workflow_variable, :url_type)
          
          expect(variable.validate_value('https://example.com')).to be true
          expect(variable.validate_value('not-a-url')).to be false
        end

        it 'validates date format' do
          variable = create(:ai_workflow_variable, :date_type)
          
          expect(variable.validate_value('2024-01-15')).to be true
          expect(variable.validate_value('invalid-date')).to be false
        end
      end
    end

    describe '#coerce_value' do
      it 'coerces string to appropriate type' do
        number_var = create(:ai_workflow_variable, :number_type)
        expect(number_var.coerce_value('42.5')).to eq(42.5)

        integer_var = create(:ai_workflow_variable, :integer_type)
        expect(integer_var.coerce_value('42')).to eq(42)

        boolean_var = create(:ai_workflow_variable, :boolean_type)
        expect(boolean_var.coerce_value('true')).to be true
        expect(boolean_var.coerce_value('false')).to be false
      end

      it 'handles array parsing from JSON strings' do
        array_var = create(:ai_workflow_variable, :array_type)
        expect(array_var.coerce_value('["item1", "item2"]')).to eq(['item1', 'item2'])
      end

      it 'handles object parsing from JSON strings' do
        object_var = create(:ai_workflow_variable, :object_type)
        result = object_var.coerce_value('{"name": "test", "value": 42}')
        expect(result).to eq({ 'name' => 'test', 'value' => 42 })
      end

      it 'returns original value if coercion fails' do
        number_var = create(:ai_workflow_variable, :number_type)
        expect(number_var.coerce_value('not_a_number')).to eq('not_a_number')
      end
    end

    describe '#resolve_value' do
      let(:variable) { create(:ai_workflow_variable, :string_type, default_value: 'default') }

      it 'returns provided value when given' do
        expect(variable.resolve_value('provided')).to eq('provided')
      end

      it 'returns default value when no value provided' do
        expect(variable.resolve_value(nil)).to eq('default')
      end

      it 'validates resolved value' do
        variable.validation_rules = { min_length: 10 }
        
        expect {
          variable.resolve_value('short')
        }.to raise_error(StandardError, /validation failed/i)
      end

      it 'coerces value to correct type' do
        number_var = create(:ai_workflow_variable, :number_type, default_value: 0)
        expect(number_var.resolve_value('42')).to eq(42)
      end
    end

    describe '#encrypted_value' do
      let(:variable) { create(:ai_workflow_variable, :sensitive) }

      it 'encrypts sensitive values' do
        encrypted = variable.encrypted_value('secret_password')
        expect(encrypted).not_to eq('secret_password')
        expect(encrypted).to be_present
      end

      it 'returns nil for non-sensitive variables' do
        regular_var = create(:ai_workflow_variable, :string_type)
        expect(regular_var.encrypted_value('value')).to be_nil
      end
    end

    describe '#decrypt_value' do
      let(:variable) { create(:ai_workflow_variable, :sensitive) }

      it 'decrypts previously encrypted values' do
        original = 'secret_password'
        encrypted = variable.encrypted_value(original)
        decrypted = variable.decrypt_value(encrypted)
        
        expect(decrypted).to eq(original)
      end

      it 'returns nil for invalid encrypted data' do
        expect(variable.decrypt_value('invalid_encrypted_data')).to be_nil
      end
    end

    describe '#masked_value' do
      it 'masks sensitive variable values' do
        sensitive_var = create(:ai_workflow_variable, :sensitive)
        expect(sensitive_var.masked_value('secret123')).to eq('***')
      end

      it 'returns actual value for non-sensitive variables' do
        regular_var = create(:ai_workflow_variable, :string_type)
        expect(regular_var.masked_value('public_value')).to eq('public_value')
      end

      it 'partially masks long values' do
        sensitive_var = create(:ai_workflow_variable, :sensitive)
        long_secret = 'very_long_secret_password_123'
        masked = sensitive_var.masked_value(long_secret)
        
        expect(masked).to start_with('very')
        expect(masked).to end_with('***')
      end
    end

    describe '#variable_summary' do
      let(:variable) { create(:ai_workflow_variable, :string_type, description: 'Test variable') }

      it 'returns comprehensive variable information' do
        summary = variable.variable_summary
        
        expect(summary).to include(
          :name,
          :variable_type,
          :description,
          :is_required,
          :is_sensitive,
          :default_value,
          :validation_rules,
          :usage_context
        )
        
        expect(summary[:name]).to eq(variable.name)
        expect(summary[:variable_type]).to eq('string')
      end

      it 'masks sensitive information in summary' do
        sensitive_var = create(:ai_workflow_variable, :sensitive, default_value: nil)
        summary = sensitive_var.variable_summary
        
        expect(summary[:is_sensitive]).to be true
        expect(summary[:default_value]).to be_nil # Should not expose sensitive defaults
      end
    end
  end

  describe 'class methods' do
    describe '.validate_variables_against_schema' do
      let(:workflow) { create(:ai_workflow) }
      let!(:required_var) { create(:ai_workflow_variable, :required, 
                                  ai_workflow: workflow, 
                                  name: 'api_key',
                                  variable_type: 'string') }
      let!(:optional_var) { create(:ai_workflow_variable,
                                  ai_workflow: workflow,
                                  name: 'timeout',
                                  variable_type: 'integer',
                                  default_value: 30) }

      it 'validates complete variable set against workflow schema' do
        valid_values = { 'api_key' => 'sk-test123', 'timeout' => 60 }
        result = described_class.validate_variables_against_schema(workflow.id, valid_values)
        
        expect(result[:valid]).to be true
        expect(result[:resolved_values]).to include('api_key' => 'sk-test123', 'timeout' => 60)
      end

      it 'applies default values for missing optional variables' do
        partial_values = { 'api_key' => 'sk-test123' }
        result = described_class.validate_variables_against_schema(workflow.id, partial_values)
        
        expect(result[:valid]).to be true
        expect(result[:resolved_values]['timeout']).to eq(30)
      end

      it 'reports missing required variables' do
        incomplete_values = { 'timeout' => 60 }
        result = described_class.validate_variables_against_schema(workflow.id, incomplete_values)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/api_key.*required/i))
      end

      it 'validates individual variable constraints' do
        invalid_values = { 'api_key' => '', 'timeout' => -1 }
        result = described_class.validate_variables_against_schema(workflow.id, invalid_values)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to be_present
      end
    end

    describe '.extract_variables_from_content' do
      it 'extracts variable references from template strings' do
        content = 'Hello {{user_name}}, your order {{order_id}} is ready. Total: {{total_amount}}'
        variables = described_class.extract_variables_from_content(content)
        
        expect(variables).to contain_exactly('user_name', 'order_id', 'total_amount')
      end

      it 'handles nested variable references' do
        content = 'Config: {{config.api.endpoint}} with key {{config.api.key}}'
        variables = described_class.extract_variables_from_content(content)
        
        expect(variables).to include('config.api.endpoint', 'config.api.key')
      end

      it 'deduplicates repeated variable references' do
        content = 'User {{user_id}} has {{user_id}} permissions for {{user_id}}'
        variables = described_class.extract_variables_from_content(content)
        
        expect(variables).to eq(['user_id'])
      end
    end

    describe '.generate_schema_from_variables' do
      let(:workflow) { create(:ai_workflow) }

      before do
        create(:ai_workflow_variable, :string_type, ai_workflow: workflow, name: 'title', is_required: true)
        create(:ai_workflow_variable, :integer_type, ai_workflow: workflow, name: 'count', default_value: 1)
        create(:ai_workflow_variable, :boolean_type, ai_workflow: workflow, name: 'active', default_value: true)
      end

      it 'generates JSON schema from workflow variables' do
        schema = described_class.generate_schema_from_variables(workflow.id)
        
        expect(schema[:type]).to eq('object')
        expect(schema[:required]).to include('title')
        expect(schema[:properties]).to have_key(:title)
        expect(schema[:properties]).to have_key(:count)
        expect(schema[:properties][:title][:type]).to eq('string')
        expect(schema[:properties][:count][:type]).to eq('integer')
      end

      it 'includes validation constraints in schema' do
        workflow.ai_workflow_variables.first.update!(
          validation_rules: { min_length: 5, max_length: 100 }
        )
        
        schema = described_class.generate_schema_from_variables(workflow.id)
        title_props = schema[:properties][:title]
        
        expect(title_props[:minLength]).to eq(5)
        expect(title_props[:maxLength]).to eq(100)
      end
    end

    describe '.create_from_template' do
      let(:workflow) { create(:ai_workflow) }
      let(:template_variables) {
        [
          { name: 'api_endpoint', type: 'url', required: true, description: 'API endpoint URL' },
          { name: 'batch_size', type: 'integer', required: false, default_value: 100 },
          { name: 'api_key', type: 'password', required: true, sensitive: true }
        ]
      }

      it 'creates variables from template definition' do
        expect {
          described_class.create_from_template(workflow, template_variables)
        }.to change { workflow.ai_workflow_variables.count }.by(3)
        
        api_key_var = workflow.ai_workflow_variables.find_by(name: 'api_key')
        expect(api_key_var.variable_type).to eq('password')
        expect(api_key_var.is_sensitive).to be true
        expect(api_key_var.is_required).to be true
      end

      it 'skips duplicate variable names' do
        create(:ai_workflow_variable, ai_workflow: workflow, name: 'api_endpoint')
        
        expect {
          described_class.create_from_template(workflow, template_variables)
        }.to change { workflow.ai_workflow_variables.count }.by(2) # Skips existing api_endpoint
      end
    end
  end

  describe 'performance and edge cases' do
    describe 'complex validation scenarios' do
      it 'handles deeply nested object validation efficiently' do
        variable = create(:ai_workflow_variable, :object_type)
        variable.validation_rules = {
          properties: {
            level1: {
              type: 'object',
              properties: {
                level2: {
                  type: 'object',
                  properties: {
                    level3: { type: 'string', min_length: 5 }
                  }
                }
              }
            }
          }
        }
        
        deep_object = {
          level1: {
            level2: {
              level3: 'valid_value'
            }
          }
        }
        
        expect(variable.validate_value(deep_object)).to be true
      end

      it 'handles large array validation efficiently' do
        variable = create(:ai_workflow_variable, :array_type)
        variable.validation_rules = {
          max_items: 10000,
          item_type: 'string',
          unique_items: true
        }
        
        large_array = Array.new(5000) { |i| "item_#{i}" }
        
        expect { variable.validate_value(large_array) }.not_to exceed_query_limit(1)
        expect(variable.validate_value(large_array)).to be true
      end
    end

    describe 'unicode and special character handling' do
      it 'handles unicode in variable names and values' do
        variable = create(:ai_workflow_variable, :string_type, 
                         name: 'unicode_测试',
                         description: 'Unicode test variable with émojis 🚀',
                         default_value: '你好世界')
        
        expect(variable).to be_valid
        expect(variable.validate_value('测试值 🎉')).to be true
      end

      it 'handles special characters in validation patterns' do
        variable = create(:ai_workflow_variable, :string_type)
        variable.validation_rules = { pattern: '^[\\p{L}\\p{N}\\p{Pd}\\p{Pc}]+$' } # Unicode word characters
        
        expect(variable.validate_value('test-value_123')).to be true
        expect(variable.validate_value('测试-值_123')).to be true
        expect(variable.validate_value('invalid@value')).to be false
      end
    end

    describe 'encryption and security edge cases' do
      it 'handles encryption failures gracefully' do
        variable = create(:ai_workflow_variable, :sensitive)
        
        # Mock encryption failure
        allow(variable).to receive(:encrypt_data).and_raise(StandardError, 'Encryption failed')
        
        expect { variable.encrypted_value('secret') }.not_to raise_error
        expect(variable.encrypted_value('secret')).to be_nil
      end

      it 'prevents timing attacks on sensitive value comparison' do
        variable = create(:ai_workflow_variable, :sensitive)
        
        # Should take similar time regardless of value length
        short_value = 'a'
        long_value = 'a' * 1000
        
        start_time = Time.current
        variable.validate_value(short_value)
        short_duration = Time.current - start_time
        
        start_time = Time.current
        variable.validate_value(long_value)
        long_duration = Time.current - start_time
        
        # Duration difference should be minimal (< 10ms)
        expect((long_duration - short_duration).abs).to be < 0.01
      end
    end

    describe 'concurrent variable operations' do
      it 'handles concurrent variable validation safely' do
        variable = create(:ai_workflow_variable, :string_type)
        
        threads = 10.times.map do
          Thread.new do
            variable.validate_value("test_value_#{rand(1000)}")
          end
        end
        
        results = threads.map(&:value)
        expect(results.all?).to be true
      end
    end

    describe 'query performance with large variable sets' do
      before do
        workflow = create(:ai_workflow)
        create_list(:ai_workflow_variable, 100, ai_workflow: workflow)
      end

      it 'efficiently validates large variable sets' do
        workflow = AiWorkflow.joins(:ai_workflow_variables).first
        values = workflow.ai_workflow_variables.index_by(&:name).transform_values { |v| v.default_value || 'test' }
        
        expect {
          described_class.validate_variables_against_schema(workflow.id, values)
        }.not_to exceed_query_limit(3)
      end

      it 'efficiently generates schema for many variables' do
        workflow = AiWorkflow.joins(:ai_workflow_variables).first
        
        expect {
          described_class.generate_schema_from_variables(workflow.id)
        }.not_to exceed_query_limit(1)
      end
    end

    describe 'memory usage with large values' do
      it 'handles large string values efficiently' do
        variable = create(:ai_workflow_variable, :text_type)
        large_text = 'Lorem ipsum ' * 10000 # ~110KB text
        
        expect { variable.validate_value(large_text) }.not_to raise_error
        expect(variable.validate_value(large_text)).to be true
      end

      it 'handles large object values efficiently' do
        variable = create(:ai_workflow_variable, :json_type)
        large_object = {
          data: Array.new(1000) { |i| { id: i, content: "Content #{i}" * 50 } }
        }
        
        expect { variable.validate_value(large_object) }.not_to raise_error
        expect(variable.validate_value(large_object)).to be true
      end
    end
  end
end