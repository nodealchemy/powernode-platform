# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataManagement::Sanitizer do
  describe '.sanitize_string' do
    it 'masks credit card numbers' do
      input = 'Please charge 4242424242424242 for the order'
      result = described_class.sanitize_string(input)
      expect(result).to include('4242********4242')
      expect(result).not_to include('4242424242424242')
    end

    it 'masks CVV codes' do
      input = 'CVV: 123 and CVC 456'
      result = described_class.sanitize_string(input)
      expect(result).to include('***')
    end

    it 'masks multiple sensitive patterns' do
      input = 'Card: 4242424242424242, CVV: 123, Exp: 12/25'
      result = described_class.sanitize_string(input)
      expect(result).not_to include('4242424242424242')
      expect(result).to include('4242********4242')
      expect(result).to include('***') # CVV gets masked to ***
      expect(result).to include('**/**') # Exp gets masked
    end

    it 'handles non-string input safely' do
      expect(described_class.sanitize_string(nil)).to be_nil
      expect(described_class.sanitize_string(123)).to eq(123)
    end
  end

  describe '.sanitize_hash' do
    it 'sanitizes sensitive keys' do
      hash = {
        'card_number' => '4242424242424242',
        'cvv' => '123',
        'normal_field' => 'safe data'
      }
      result = described_class.sanitize_hash(hash)

      expect(result['card_number']).to eq('4242********4242')
      expect(result['cvv']).to eq('***')
      expect(result['normal_field']).to eq('safe data')
    end

    it 'handles nested hashes' do
      hash = {
        'payment' => {
          'card_number' => '4242424242424242',
          'metadata' => {
            'customer_id' => 'safe_id'
          }
        }
      }
      result = described_class.sanitize_hash(hash)

      expect(result['payment']['card_number']).to eq('4242********4242')
      expect(result['payment']['metadata']['customer_id']).to eq('safe_id')
    end

    it 'sanitizes arrays containing sensitive data' do
      hash = {
        'cards' => [ '4242424242424242', '5555555555554444' ],
        'safe_array' => [ 'item1', 'item2' ]
      }
      result = described_class.sanitize_hash(hash)

      expect(result['cards'][0]).to eq('4242********4242')
      expect(result['cards'][1]).to eq('5555********4444')
      expect(result['safe_array']).to eq([ 'item1', 'item2' ])
    end
  end

  describe '.contains_sensitive_data?' do
    it 'detects credit card numbers' do
      expect(described_class.contains_sensitive_data?('4242424242424242')).to be_truthy
      expect(described_class.contains_sensitive_data?('safe text')).to be_falsy
    end

    it 'detects CVV codes' do
      expect(described_class.contains_sensitive_data?('cvv 123')).to be_truthy
      expect(described_class.contains_sensitive_data?('normal text')).to be_falsy
    end

    it 'handles non-string input' do
      expect(described_class.contains_sensitive_data?(nil)).to be_falsy
      expect(described_class.contains_sensitive_data?(123)).to be_falsy
    end
  end

  describe '.sanitization_summary' do
    it 'provides sanitization summary' do
      original = 'Card: 4242424242424242'
      sanitized = described_class.sanitize_string(original)
      summary = described_class.sanitization_summary(original, sanitized)

      expect(summary).to include(:original_length)
      expect(summary).to include(:sanitized_length)
      expect(summary).to include(:patterns_found)
      expect(summary[:patterns_found]).to include('credit_card')
    end
  end

  describe 'instance methods' do
    let(:sanitizer) { described_class.new('test_context') }

    describe '#sanitize_for_logging' do
      it 'sanitizes hash data for logging' do
        data = { 'card_number' => '4242424242424242' }
        result = sanitizer.sanitize_for_logging(data)
        expect(result['card_number']).to eq('4242********4242')
      end

      it 'sanitizes string data for logging' do
        data = 'Card number is 4242424242424242'
        result = sanitizer.sanitize_for_logging(data)
        expect(result).to include('4242********4242')
      end
    end

    describe '#safe_to_log?' do
      it 'returns true for safe data' do
        expect(sanitizer.safe_to_log?('safe data')).to be_truthy
      end

      it 'returns false for sensitive data' do
        expect(sanitizer.safe_to_log?('4242424242424242')).to be_falsy
      end
    end
  end
end
