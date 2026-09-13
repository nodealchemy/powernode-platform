require 'rails_helper'

RSpec.describe AdminSetting, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      setting = AdminSetting.new(key: 'test_setting', value: 'test_value')
      expect(setting).to be_valid
    end

    it 'requires a key' do
      setting = AdminSetting.new(value: 'test_value')
      expect(setting).not_to be_valid
      expect(setting.errors[:key]).to include("can't be blank")
    end

    it 'requires unique keys' do
      AdminSetting.create!(key: 'duplicate_key', value: 'value1')
      setting = AdminSetting.new(key: 'duplicate_key', value: 'value2')
      expect(setting).not_to be_valid
      expect(setting.errors[:key]).to include('has already been taken')
    end

    it 'allows empty values' do
      setting = AdminSetting.new(key: 'test_key', value: '')
      expect(setting).to be_valid
    end
  end

  describe 'scopes and class methods' do
    before do
      AdminSetting.create!(key: 'setting1', value: 'value1')
      AdminSetting.create!(key: 'setting2', value: 'value2')
    end

    it 'can find settings by key' do
      setting = AdminSetting.find_by(key: 'setting1')
      expect(setting.value).to eq('value1')
    end

    it 'returns all settings' do
      expect(AdminSetting.count).to eq(2)
    end
  end

  describe 'JSON value handling' do
    it 'can store JSON values' do
      json_value = { 'config' => { 'enabled' => true, 'limit' => 100 } }.to_json
      setting = AdminSetting.create!(key: 'json_setting', value: json_value)
      expect(setting.value).to eq(json_value)
    end

    it 'can parse JSON values' do
      json_data = { 'enabled' => true, 'limit' => 100 }
      setting = AdminSetting.create!(key: 'json_setting', value: json_data.to_json)
      parsed = JSON.parse(setting.value)
      expect(parsed['enabled']).to be true
      expect(parsed['limit']).to eq(100)
    end
  end

  describe 'boolean value handling' do
    it 'can store boolean-like string values' do
      setting = AdminSetting.create!(key: 'boolean_setting', value: 'true')
      expect(setting.value).to eq('true')
    end

    it 'can check boolean values' do
      true_setting = AdminSetting.create!(key: 'enabled', value: 'true')
      false_setting = AdminSetting.create!(key: 'disabled', value: 'false')

      expect(true_setting.value == 'true').to be true
      expect(false_setting.value == 'false').to be true
    end
  end

  # secreview §22: the stored value for this key is TRUSTED AS-IS everywhere
  # it's read. A garbage value must never turn into an instant-expiry (0/negative),
  # a 500 (a JSON boolean/object/array), or an effectively-infinite window
  # (an absurdly large number). This is the single reader both User#email_verification_expired?
  # and the email settings API (what notification_mailer.rb promises) call through,
  # so the two can't drift.
  describe '.email_verification_expiry_hours' do
    after { AdminSetting.where(key: 'email_verification_expiry_hours').delete_all }

    it 'defaults to 24 when no row exists' do
      expect(AdminSetting.email_verification_expiry_hours).to eq(24)
    end

    {
      '0' => 24, '-5' => 24, 'abc' => 24, '' => 24,
      'true' => 24, '[1,2,3]' => 24, '{"a":1}' => 24,
      '1000000' => 720, '1e20' => 720,
      '12' => 12, '720' => 720, '721' => 720,
      # secreview §25: Integer() without an explicit base reads a leading-zero
      # or "0x"-prefixed string as octal/hex, not decimal, and doesn't rescue
      # FloatDomainError for a stored value so large it JSON-parses to Infinity.
      '010' => 10, '0x10' => 24, '1e400' => 24,
    }.each do |raw, expected|
      it "reads #{raw.inspect} as #{expected}" do
        AdminSetting.set('email_verification_expiry_hours', raw)
        expect(AdminSetting.email_verification_expiry_hours).to eq(expected)
      end
    end
  end

  describe 'audit trail' do
    it 'has timestamps' do
      setting = AdminSetting.create!(key: 'timestamped', value: 'test')
      expect(setting.created_at).to be_present
      expect(setting.updated_at).to be_present
    end

    it 'updates timestamp on value change' do
      setting = AdminSetting.create!(key: 'changeable', value: 'original')
      original_time = setting.updated_at

      sleep(0.1) # Ensure time difference
      setting.update!(value: 'changed')

      expect(setting.updated_at).to be > original_time
    end
  end
end
