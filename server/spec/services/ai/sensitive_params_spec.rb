# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SensitiveParams do
  describe '.filter' do
    it 'masks a secret-looking key and leaves the rest legible' do
      filtered = described_class.filter(
        'federation_peer_id' => 'peer-42',
        'acceptance_token' => 'PLAINTEXT'
      )

      expect(filtered['acceptance_token']).to eq('[FILTERED]')
      expect(filtered['federation_peer_id']).to eq('peer-42')
    end

    it 'matches as a substring, so a decorated key name is still caught' do
      filtered = described_class.filter('acceptance_token_plaintext' => 'PLAINTEXT')

      expect(filtered['acceptance_token_plaintext']).to eq('[FILTERED]')
    end

    it 'matches case-insensitively' do
      expect(described_class.filter('API_KEY' => 'PLAINTEXT')['API_KEY']).to eq('[FILTERED]')
    end

    it 'handles symbol keys, since executor results are symbol-keyed hashes' do
      filtered = described_class.filter(success: true, data: { acceptance_token: 'PLAINTEXT' })

      expect(filtered.dig(:data, :acceptance_token)).to eq('[FILTERED]')
      expect(filtered[:success]).to be true
    end

    it 'traverses nested hashes and arrays' do
      filtered = described_class.filter(
        'attributes' => { 'peers' => [{ 'name' => 'a', 'client_secret' => 'PLAINTEXT' }] }
      )

      expect(filtered.dig('attributes', 'peers', 0, 'client_secret')).to eq('[FILTERED]')
      expect(filtered.dig('attributes', 'peers', 0, 'name')).to eq('a')
    end

    it 'does not mutate the hash it was given' do
      original = { 'acceptance_token' => 'PLAINTEXT' }
      described_class.filter(original)

      expect(original['acceptance_token']).to eq('PLAINTEXT')
    end

    it 'returns non-Hash input unchanged' do
      expect(described_class.filter(nil)).to be_nil
      expect(described_class.filter('a string')).to eq('a string')
      expect(described_class.filter([1, 2])).to eq([1, 2])
    end

    # Matching is on KEYS, never values. The disk-image webhook rotation gates
    # with params { webhook_id:, action: "rotate_secret" } — a value that reads
    # like a secret and is not one. Redacting it would blank the only field
    # telling the approver WHICH webhook action they are approving.
    it 'judges the key, not the value' do
      filtered = described_class.filter('webhook_id' => 'wh-1', 'action' => 'rotate_secret')

      expect(filtered['action']).to eq('rotate_secret')
      expect(filtered['webhook_id']).to eq('wh-1')
    end

    # The same rotation's RESULT does carry the real thing, under a key named
    # for it. That executor is a second, unrelated producer of secret material
    # through the same gate — covered here without knowing it exists, which is
    # the point of matching on a pattern rather than a declared field list.
    it 'masks a minted secret in an executor result from an unrelated subsystem' do
      filtered = described_class.filter(
        success: true,
        data: { webhook_id: 'wh-1', action: 'rotate_secret', secret_plaintext: 'HMAC-PLAINTEXT' }
      )

      expect(filtered.dig(:data, :secret_plaintext)).to eq('[FILTERED]')
      expect(filtered.dig(:data, :action)).to eq('rotate_secret')
    end

    # The list is tuned for secret material, NOT reused from Rails'
    # filter_parameters — blanking an approver's view of who requested what
    # would be its own failure. This pins the deliberate omission.
    it 'leaves non-secret context that an approver needs to decide' do
      filtered = described_class.filter(
        'requested_by_email' => 'op@example.com',
        'certificate' => 'PUBLIC-PEM',
        'action_category' => 'sdwan.federation_peer_accept'
      )

      expect(filtered['requested_by_email']).to eq('op@example.com')
      expect(filtered['certificate']).to eq('PUBLIC-PEM')
      expect(filtered['action_category']).to eq('sdwan.federation_peer_accept')
    end
  end

  describe '.key_patterns' do
    it 'extends the defaults with the configured setting rather than replacing them' do
      SiteSetting.create!(
        key: described_class::SETTING_KEY, setting_type: 'json',
        value: '["cvv","house_style_nonce"]'
      )

      expect(described_class.key_patterns).to include('token', 'cvv', 'house_style_nonce')
      expect(described_class.filter('house_style_nonce' => 'PLAINTEXT')['house_style_nonce'])
        .to eq('[FILTERED]')
      # baseline still applies
      expect(described_class.filter('acceptance_token' => 'PLAINTEXT')['acceptance_token'])
        .to eq('[FILTERED]')
    end

    it 'falls back to the defaults when the setting is absent' do
      expect(described_class.key_patterns).to eq(described_class::DEFAULT_KEY_PATTERNS)
    end
  end
end
