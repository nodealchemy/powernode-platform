# frozen_string_literal: true

require 'rails_helper'

# IMP-77645b94151e — the substring key-match over-redacts approver-facing keys.
#
# `Ai::SensitiveParams` matches "token" as a SUBSTRING, which is right for
# acceptance_token/acceptance_token_plaintext and wrong for three keys that
# ride the same payloads and hold no material:
#
#   generate_token              boolean instruction ("mint a token or don't")
#   token_ttl_seconds           integer duration
#   acceptance_token_expires_at ISO8601 timestamp on the persisted result
#
# Those are exactly the fields an approver needs to judge a federation propose
# request, and the expiry is the only thing on the durable row telling anyone
# how long the handshake has. Over-redaction on a card an operator must ACT on
# is its own failure, distinct from a leak — the class doc says so, and these
# three are where it happens.
#
# Deliberately a SEPARATE file: spec/services/ai/sensitive_params_spec.rb is the
# oracle that nothing secret un-masks, and it stays untouched.
RSpec.describe Ai::SensitiveParams do
  # Key names are written as LITERALS throughout, never derived from
  # SAFE_KEY_ALLOWLIST. An oracle that reads its expectation off the constant
  # under test cannot see a change to that constant.
  describe 'safe-key allowlist' do
    # The payload shape a federation propose actually produces: two control
    # flags an approver must see, sitting beside the mint they must not.
    let(:propose_payload) do
      {
        'federation_peer_id' => 'peer-42',
        'attributes' => {
          'generate_token' => true,
          'token_ttl_seconds' => 900
        },
        'acceptance_token' => 'PLAINTEXT'
      }
    end

    it 'leaves generate_token and token_ttl_seconds legible on the approval card' do
      filtered = described_class.filter(propose_payload)

      expect(filtered.dig('attributes', 'generate_token')).to be true
      expect(filtered.dig('attributes', 'token_ttl_seconds')).to eq(900)
    end

    # Positive control, in the SAME payload: the whole point is that unmasking
    # the flags does not unmask the mint riding beside them.
    it 'still masks the secret sibling in the same payload' do
      filtered = described_class.filter(propose_payload)

      expect(filtered['acceptance_token']).to eq('[FILTERED]')
      expect(filtered['federation_peer_id']).to eq('peer-42')
    end

    # The persisted :result row. acceptance_token_plaintext must stay masked at
    # rest (reveal-once lives elsewhere); the expiry beside it is collateral
    # damage from the shared substring and must survive.
    it 'leaves acceptance_token_expires_at on the result while masking the mint' do
      filtered = described_class.filter(
        success: true,
        data: {
          acceptance_token_plaintext: 'PLAINTEXT',
          acceptance_token_expires_at: '2026-08-23T00:00:00Z'
        }
      )

      expect(filtered.dig(:data, :acceptance_token_expires_at)).to eq('2026-08-23T00:00:00Z')
      expect(filtered.dig(:data, :acceptance_token_plaintext)).to eq('[FILTERED]')
    end

    it 'allowlists case-insensitively, matching how the patterns themselves match' do
      filtered = described_class.filter('GENERATE_TOKEN' => true, 'Token_TTL_Seconds' => 60)

      expect(filtered['GENERATE_TOKEN']).to be true
      expect(filtered['Token_TTL_Seconds']).to eq(60)
    end

    # The allowlist is EXACT-match while the patterns are substring — asymmetric
    # on purpose. A decorated variant of an allowlisted name is a different key
    # that nobody has vouched for, so it keeps failing closed.
    it 'does not extend the allowlist to decorated variants of an allowlisted key' do
      filtered = described_class.filter(
        'generate_token_plaintext' => 'PLAINTEXT',
        'peer_generate_token' => 'PLAINTEXT',
        'token_ttl_seconds_secret' => 'PLAINTEXT'
      )

      expect(filtered.values).to all(eq('[FILTERED]'))
    end

    # Anchoring the allowlist to the whole key means the matcher is anchored
    # too, so the pattern half has to be able to reach across a line break —
    # otherwise a key carrying one walks past the alternation unmasked.
    it 'masks a secret-looking key that carries a line break' do
      filtered = described_class.filter("attributes\nacceptance_token" => 'PLAINTEXT')

      expect(filtered["attributes\nacceptance_token"]).to eq('[FILTERED]')
    end

    # The allowlist is checked BEFORE every substring pattern, the deployment
    # setting's included. A deployment cannot re-mask a key core has declared
    # non-secret; it can only ADD patterns for keys that are.
    it 'wins over a deployment-configured pattern' do
      SiteSetting.create!(
        key: 'ai_sensitive_param_keys', setting_type: 'json',
        value: '["ttl","house_style_nonce"]'
      )

      filtered = described_class.filter(
        'token_ttl_seconds' => 900, 'house_style_nonce' => 'PLAINTEXT'
      )

      expect(filtered['token_ttl_seconds']).to eq(900)
      expect(filtered['house_style_nonce']).to eq('[FILTERED]')
    end

    # Self-consistency: an entry that no pattern would have masked anyway is
    # either a typo or dead weight, and either way it misleads the next reader
    # into thinking a key is contested when it is not.
    it 'carries no allowlist entry that the patterns would not otherwise mask' do
      inert = described_class::SAFE_KEY_ALLOWLIST.reject do |key|
        described_class::DEFAULT_KEY_PATTERNS.any? { |p| key.downcase.include?(p) }
      end

      expect(inert).to be_empty
    end
  end

  # The filter and its ai_sensitive_param_keys lookup were rebuilt per filtered
  # ROW: the approvals queue serializes N requests and paid for N pattern
  # resolutions and N regexp compilations. `.batch` resolves once for the
  # duration of a block — scoped to that block and torn down in `ensure`, never
  # a process-wide or cross-request cache, so a setting change is visible to the
  # very next batch.
  describe '.batch' do
    before { allow(SiteSetting).to receive(:get).and_call_original }

    it 'resolves the configured pattern set once for many filtered payloads' do
      described_class.batch do
        3.times { |i| described_class.filter('acceptance_token' => "PLAINTEXT-#{i}") }
      end

      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').once
    end

    # Positive control for the example above: without the block each call
    # resolves on its own, so the "once" is the block's doing and not an
    # artifact of the setting being absent.
    it 'resolves per call when no block is open' do
      3.times { |i| described_class.filter('acceptance_token' => "PLAINTEXT-#{i}") }

      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').exactly(3).times
    end

    it 'does not carry the resolution across two blocks' do
      2.times { described_class.batch { described_class.filter('acceptance_token' => 'PLAINTEXT') } }

      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').exactly(2).times
    end

    # The staleness consequence of "not cross-request", stated as behaviour: a
    # pattern added between batches takes effect immediately.
    it 'sees a setting written between blocks' do
      described_class.batch { described_class.filter('house_style_nonce' => 'PLAINTEXT') }

      SiteSetting.create!(
        key: 'ai_sensitive_param_keys', setting_type: 'json', value: '["house_style_nonce"]'
      )

      filtered = described_class.batch { described_class.filter('house_style_nonce' => 'PLAINTEXT') }
      expect(filtered['house_style_nonce']).to eq('[FILTERED]')
    end

    # A memo left behind by a raising block would be exactly the cross-request
    # cache this must not become — the next request on the same thread would
    # inherit it.
    it 'tears the memo down when the block raises' do
      expect { described_class.batch { raise ArgumentError, 'boom' } }.to raise_error(ArgumentError)

      described_class.filter('acceptance_token' => 'PLAINTEXT')
      described_class.filter('acceptance_token' => 'PLAINTEXT')

      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').exactly(2).times
    end

    it 'returns the block value and filters identically inside and out' do
      payload = { 'acceptance_token' => 'PLAINTEXT', 'generate_token' => false }
      inside = described_class.batch { described_class.filter(payload) }

      expect(inside).to eq(described_class.filter(payload))
      expect(inside['acceptance_token']).to eq('[FILTERED]')
      expect(inside['generate_token']).to be false
    end

    it 'reuses the outer resolution when nested' do
      described_class.batch do
        described_class.filter('acceptance_token' => 'PLAINTEXT')
        described_class.batch { described_class.filter('acceptance_token' => 'PLAINTEXT') }
      end

      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').once
    end
  end
end
