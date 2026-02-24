# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SiteSetting, type: :model do
  subject { build(:site_setting) }

  describe 'validations' do
    it { should validate_presence_of(:key) }
    it { should validate_presence_of(:setting_type) }
    it { should validate_inclusion_of(:setting_type).in_array(%w[string text boolean integer json]) }

    it 'validates key uniqueness case-insensitively' do
      existing_setting = create(:site_setting)
      duplicate = build(:site_setting, key: existing_setting.key.upcase)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to include('has already been taken')
    end

    describe 'value validation' do
      it 'requires value for string settings' do
        setting = build(:site_setting, :string_setting, value: '')
        expect(setting).not_to be_valid
        expect(setting.errors[:value]).to include("can't be blank")
      end

      it 'requires value for text settings' do
        setting = build(:site_setting, :text_setting, value: '')
        expect(setting).not_to be_valid
        expect(setting.errors[:value]).to include("can't be blank")
      end

      it 'allows empty value for boolean settings' do
        setting = build(:site_setting, :boolean_setting, value: '')
        expect(setting).to be_valid
      end

      it 'allows empty value for social settings' do
        setting = build(:site_setting, key: 'social_twitter', value: '', setting_type: 'string')
        expect(setting).to be_valid
      end

      it 'allows empty value for analytics tracking ID' do
        setting = build(:site_setting, key: 'analytics_tracking_id', value: '', setting_type: 'string')
        expect(setting).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:public_setting) { create(:site_setting, :public_setting) }
    let!(:private_setting) { create(:site_setting) }
    let!(:footer_setting) { create(:site_setting, :footer_setting) }
    let!(:string_setting) { create(:site_setting, :string_setting) }
    let!(:boolean_setting) { create(:site_setting, :boolean_setting) }

    describe '.public_settings' do
      it 'returns only public settings' do
        expect(SiteSetting.public_settings).to include(public_setting, footer_setting)
        expect(SiteSetting.public_settings).not_to include(private_setting)
      end
    end

    describe '.by_type' do
      it 'returns settings of specific type' do
        expect(SiteSetting.by_type('string')).to include(string_setting)
        expect(SiteSetting.by_type('boolean')).to include(boolean_setting)
        expect(SiteSetting.by_type('string')).not_to include(boolean_setting)
      end
    end

    describe '.footer_settings' do
      it 'returns only footer settings' do
        footer_records = SiteSetting.where(key: SiteSetting.footer_keys)
        expect(SiteSetting.footer_settings).to include(footer_setting.key => footer_setting.parsed_value)
        footer_records.each do |setting|
          expect(SiteSetting.footer_settings).to have_key(setting.key)
        end
      end
    end
  end

  describe 'callbacks' do
    describe 'cache clearing' do
      it 'clears footer cache when footer setting is updated' do
        footer_setting = create(:site_setting, :footer_setting)
        expect(SiteSetting).to receive(:clear_footer_cache!)
        footer_setting.update!(value: 'New Value')
      end

      it 'clears footer cache when cache toggle is updated' do
        cache_setting = create(:site_setting, key: 'footer_cache_enabled', value: 'true')
        expect(SiteSetting).to receive(:clear_footer_cache!)
        cache_setting.update!(value: 'false')
      end

      it 'does not clear cache for non-footer settings' do
        regular_setting = create(:site_setting)
        expect(SiteSetting).not_to receive(:clear_footer_cache!)
        regular_setting.update!(value: 'New Value')
      end
    end
  end

  describe '.footer_keys' do
    it 'returns expected footer keys' do
      expected_keys = %w[
        site_name copyright_text copyright_year
        social_facebook social_twitter social_linkedin
        social_instagram social_youtube footer_description
        company_address contact_email contact_phone
      ]
      expect(SiteSetting.footer_keys).to match_array(expected_keys)
    end
  end

  describe '.get' do
    context 'with string setting' do
      let!(:setting) { create(:site_setting, key: 'test_string', value: 'test value', setting_type: 'string') }

      it 'returns string value' do
        expect(SiteSetting.get('test_string')).to eq('test value')
      end
    end

    context 'with boolean setting' do
      it 'returns true for truthy values' do
        create(:site_setting, key: 'test_bool_true', value: 'true', setting_type: 'boolean')
        create(:site_setting, key: 'test_bool_1', value: '1', setting_type: 'boolean')
        create(:site_setting, key: 'test_bool_yes', value: 'yes', setting_type: 'boolean')

        expect(SiteSetting.get('test_bool_true')).to be true
        expect(SiteSetting.get('test_bool_1')).to be true
        expect(SiteSetting.get('test_bool_yes')).to be true
      end

      it 'returns false for falsy values' do
        create(:site_setting, key: 'test_bool_false', value: 'false', setting_type: 'boolean')
        create(:site_setting, key: 'test_bool_0', value: '0', setting_type: 'boolean')
        create(:site_setting, key: 'test_bool_no', value: 'no', setting_type: 'boolean')

        expect(SiteSetting.get('test_bool_false')).to be false
        expect(SiteSetting.get('test_bool_0')).to be false
        expect(SiteSetting.get('test_bool_no')).to be false
      end
    end

    context 'with integer setting' do
      let!(:setting) { create(:site_setting, key: 'test_integer', value: '123', setting_type: 'integer') }

      it 'returns integer value' do
        expect(SiteSetting.get('test_integer')).to eq(123)
      end
    end

    context 'with json setting' do
      let!(:setting) { create(:site_setting, key: 'test_json', value: '{"key": "value"}', setting_type: 'json') }

      it 'returns parsed JSON' do
        expect(SiteSetting.get('test_json')).to eq({ 'key' => 'value' })
      end

      it 'returns empty hash for invalid JSON' do
        create(:site_setting, key: 'invalid_json', value: 'invalid json', setting_type: 'json')
        expect(SiteSetting.get('invalid_json')).to eq({})
      end
    end

    context 'with non-existent setting' do
      it 'returns nil' do
        expect(SiteSetting.get('non_existent')).to be_nil
      end
    end
  end

  describe '.set' do
    context 'creating new setting' do
      it 'creates string setting' do
        setting = SiteSetting.set('new_string', 'value', description: 'Test desc', setting_type: 'string')

        expect(setting).to be_persisted
        expect(setting.key).to eq('new_string')
        expect(setting.value).to eq('value')
        expect(setting.description).to eq('Test desc')
        expect(setting.setting_type).to eq('string')
      end

      it 'creates boolean setting' do
        setting = SiteSetting.set('new_bool', true, setting_type: 'boolean')

        expect(setting.value).to eq('true')
        expect(setting.setting_type).to eq('boolean')
      end

      it 'creates json setting from hash' do
        data = { 'option1' => true, 'option2' => 'value' }
        setting = SiteSetting.set('new_json', data, setting_type: 'json')

        expect(setting.value).to eq(data.to_json)
        expect(setting.setting_type).to eq('json')
      end

      it 'creates json setting from string' do
        json_string = '{"option1": true}'
        setting = SiteSetting.set('new_json_string', json_string, setting_type: 'json')

        expect(setting.value).to eq(json_string)
        expect(setting.setting_type).to eq('json')
      end
    end

    context 'updating existing setting' do
      let!(:existing_setting) { create(:site_setting, key: 'existing_key', value: 'old_value') }

      it 'updates existing setting value' do
        updated = SiteSetting.set('existing_key', 'new_value')

        expect(updated.id).to eq(existing_setting.id)
        expect(updated.value).to eq('new_value')
      end

      it 'updates description if provided' do
        updated = SiteSetting.set('existing_key', 'new_value', description: 'New description')
        expect(updated.description).to eq('New description')
      end
    end
  end

  describe '.footer_settings' do
    let!(:site_name) { create(:site_setting, key: 'site_name', value: 'Test Site', is_public: true) }
    let!(:copyright) { create(:site_setting, key: 'copyright_text', value: 'Copyright 2025', is_public: true) }
    let!(:non_footer) { create(:site_setting, key: 'other_setting', value: 'other') }

    it 'returns footer settings as hash' do
      result = SiteSetting.footer_settings

      expect(result).to be_a(Hash)
      expect(result['site_name']).to eq('Test Site')
      expect(result['copyright_text']).to eq('Copyright 2025')
      expect(result).not_to have_key('other_setting')
    end
  end

  describe '.public_footer_settings' do
    let!(:site_name) { create(:site_setting, key: 'site_name', value: 'Test Site', is_public: true) }
    let!(:private_footer) { create(:site_setting, key: 'copyright_text', value: 'Private', is_public: false) }

    it 'returns only public footer settings' do
      result = SiteSetting.public_footer_settings

      expect(result).to include('site_name' => 'Test Site')
      expect(result).not_to include('copyright_text')
    end

    context 'with caching enabled' do
      before do
        create(:site_setting, key: 'footer_cache_enabled', value: 'true', setting_type: 'boolean')
      end

      it 'uses cache' do
        expect(Rails.cache).to receive(:fetch).with('site_settings:footer:public', expires_in: 1.hour)
        SiteSetting.public_footer_settings
      end
    end

    context 'with caching disabled' do
      before do
        create(:site_setting, key: 'footer_cache_enabled', value: 'false', setting_type: 'boolean')
      end

      it 'does not use cache' do
        expect(Rails.cache).not_to receive(:fetch)
        SiteSetting.public_footer_settings
      end
    end
  end

  describe '.clear_footer_cache!' do
    it 'deletes footer cache' do
      expect(Rails.cache).to receive(:delete).with('site_settings:footer:public')
      SiteSetting.clear_footer_cache!
    end
  end

  describe '#parsed_value' do
    it 'returns parsed value using class method' do
      setting = create(:site_setting, key: 'test_parsed', value: '42', setting_type: 'integer')
      expect(setting.parsed_value).to eq(42)
    end
  end

  describe 'integration scenarios' do
    it 'handles complete footer configuration' do
      # Set up footer settings
      SiteSetting.set('site_name', 'Powernode Platform', is_public: true)
      SiteSetting.set('copyright_text', '© 2026 Everett C. Haimes III', is_public: true)
      SiteSetting.set('social_twitter', 'https://twitter.com/powernode', is_public: true)
      SiteSetting.set('footer_cache_enabled', true, setting_type: 'boolean')

      # Retrieve public footer settings
      footer_data = SiteSetting.public_footer_settings

      expect(footer_data).to include(
        'site_name' => 'Powernode Platform',
        'copyright_text' => '© 2026 Everett C. Haimes III',
        'social_twitter' => 'https://twitter.com/powernode'
      )
    end

    it 'handles various setting types correctly' do
      # Create settings of different types
      SiteSetting.set('app_name', 'Test App', setting_type: 'string')
      SiteSetting.set('max_users', 100, setting_type: 'integer')
      SiteSetting.set('feature_enabled', true, setting_type: 'boolean')
      SiteSetting.set('config', { 'theme' => 'dark', 'notifications' => true }, setting_type: 'json')

      # Verify retrieval
      expect(SiteSetting.get('app_name')).to eq('Test App')
      expect(SiteSetting.get('max_users')).to eq(100)
      expect(SiteSetting.get('feature_enabled')).to be true
      expect(SiteSetting.get('config')).to eq({ 'theme' => 'dark', 'notifications' => true })
    end
  end
end
