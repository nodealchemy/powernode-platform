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

    # Identifiers must survive, and this is the one over-redaction that would
    # fail SILENTLY. The SDWAN controllers read their new record's id off the
    # RAW return value of #execute_now! (port_mappings -> :mapping_id,
    # route_policies -> :policy_id), so a pattern that started matching an _id
    # suffix would leave every request working while quietly emptying the
    # persisted audit row — nothing goes red, and the loss is only visible to
    # whoever reads ai_deferred_operations.result months later.
    it 'leaves record identifiers intact, including on the persisted copy' do
      filtered = described_class.filter(
        'mapping_id' => 'm-1', 'policy_id' => 'p-1', 'grant_id' => 'g-1',
        'device_id' => 'd-1', 'federation_peer_id' => 'peer-42', 'webhook_id' => 'wh-1',
        'acceptance_token' => 'PLAINTEXT'
      )

      expect(filtered.values_at('mapping_id', 'policy_id', 'grant_id', 'device_id',
                                'federation_peer_id', 'webhook_id'))
        .to eq(%w[m-1 p-1 g-1 d-1 peer-42 wh-1])
      expect(filtered['acceptance_token']).to eq('[FILTERED]')
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

  describe '.filter_text' do
    # Fake values, built at runtime from parts so no secret scanner reads this
    # file as carrying a credential.
    let(:s1) { %w[not a real one].join('-') }
    let(:s2) { %w[not a real two].join('-') }
    let(:s3) { %w[not a real three].join('-') }

    it 'masks the value after a secret-named key in each spelling, keeping the surrounding text' do
      text = %(RuntimeError: bad {"acceptance_token"=>"#{s1}"} password=#{s2}, api_key: #{s3}\n) +
             %({"signing_key":"#{s1}"} Authorization: Bearer #{s2}\ntail)

      filtered = described_class.filter_text(text)

      expect(filtered).not_to include(s1, s2, s3)
      expect(filtered).to start_with('RuntimeError: bad')
      expect(filtered).to end_with('tail')
    end

    it 'leaves text that names no secret alone, and passes nil through' do
      expect(described_class.filter_text('ActiveRecord::RecordNotFound: no row')).to eq('ActiveRecord::RecordNotFound: no row')
      expect(described_class.filter_text(nil)).to be_nil
    end

    it 'truncates to TEXT_LIMIT' do
      expect(described_class.filter_text('x' * 5_000).length).to eq(described_class::TEXT_LIMIT)
    end

    # The quoted value masks down to a few characters, which pulls the URL after
    # it into the 500-character output; `cut_at` says how many characters of the
    # password sit inside the scan window (all of them, or only the head).
    def text_cut_inside_url(password, cut_at:)
      opening = 'token="'
      joiner = '" postgres://svc:'
      filler = described_class::TEXT_SCAN_WINDOW - opening.length - joiner.length - cut_at
      "#{opening}#{'a' * filler}#{joiner}#{password}@db.example/app"
    end

    it 'drops the token the window cuts through, so a URL whose @ falls outside is not half-emitted' do
      password = %w[Not A Real Pw].join

      [ password.length, 4 ].each do |cut_at|
        filtered = described_class.filter_text(text_cut_inside_url(password, cut_at: cut_at))

        expect(filtered).not_to include(password[0, 4], 'svc')
        expect(filtered).to end_with('...')
      end
    end

    it 'keeps what precedes the cut token when there is whitespace to cut at' do
      text = "boom happened here #{'a' * described_class::TEXT_SCAN_WINDOW}"

      expect(described_class.filter_text(text)).to eq('boom happened here ...')
    end

    it 'emits only the marker when the window holds no whitespace at all' do
      expect(described_class.filter_text('a' * (described_class::TEXT_SCAN_WINDOW + 10))).to eq('...')
    end

    it 'does not emit the head of a Bearer credential that straddles the window' do
      secret = %w[Not A Real Bearer Value].join
      lead = 'Authorization: Bearer '
      filler = ('. ' * ((described_class::TEXT_SCAN_WINDOW - lead.length - 5) / 2))
      text = "#{filler} #{lead}#{secret}"

      expect(described_class.filter_text(text)).not_to include(secret[0, 5])
    end

    it 'stays linear on a large text and never emits an unscanned tail' do
      timed = lambda do |text|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = described_class.filter_text(text)
        [ result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started ]
      end
      # No newline and a delimiter after every value: the shape that made each
      # keyed value scan to the end of the text.
      result, elapsed = timed.call('token=a,' * 50_000)

      expect(result.length).to be <= described_class::TEXT_LIMIT
      expect(result).not_to include('token=a')
      expect(elapsed).to be < 1.0
    end

    it 'scans only the window and marks the cut, so the tail is never emitted unmasked' do
      secret = %w[not a real tail].join('-')
      text = ('.' * described_class::TEXT_SCAN_WINDOW) + " password=#{secret}"

      expect(described_class.filter_text(text)).not_to include(secret)
      expect(described_class.filter_text('x ' * described_class::TEXT_SCAN_WINDOW)).to end_with('...')
    end

    it 'bounds a large multibyte text with an unclosed bracket' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = described_class.filter_text("token: [#{'é' * 200_000}")

      expect(result).to eq('token: [FILTERED]...')
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.0
    end

    it 'masks every element of a bracketed list, not only the first' do
      filtered = described_class.filter_text(%({"api_keys"=>["#{s1}","#{s2}"], "after"=>"kept"}))

      expect(filtered).not_to include(s1, s2)
      expect(filtered).to include('"after"=>"kept"')
    end

    it 'masks through the matching bracket of a nested value' do
      filtered = described_class.filter_text(%("credential"=>{"user"=>"a","value"=>"#{s1}"}, "next"=>"kept"))

      expect(filtered).not_to include(s1)
      expect(filtered).to include('"next"=>"kept"')
    end

    it 'does not stop at a bracket that is inside a quoted string' do
      filtered = described_class.filter_text(%(secret: {"a"=>"]#{s1}", "b"=>"#{s2}"} tail))

      expect(filtered).not_to include(s1, s2)
      expect(filtered).to end_with('tail')
    end

    it 'masks a quoted value through an escaped quote' do
      filtered = described_class.filter_text(%(password="#{s1}\\"#{s2}" after))

      expect(filtered).not_to include(s1, s2)
      expect(filtered).to end_with(' after')
    end

    it 'masks an unquoted value that contains spaces to the end of the line' do
      filtered = described_class.filter_text("password=#{s1} #{s2}\nnext line")

      expect(filtered).not_to include(s1, s2)
      expect(filtered).to end_with("\nnext line")
    end

    it 'stops an unquoted value at the next key-looking delimiter' do
      filtered = described_class.filter_text("password=#{s1}, user=bob; token=#{s2}&page=2")

      expect(filtered).not_to include(s1, s2)
      expect(filtered).to include(', user=bob;')
      expect(filtered).to end_with('&page=2')
    end

    # IMP-3d275689ca7c fix round: an exception message can carry invalid UTF-8
    # (JSON::ParserError quoting a binary body), and a regexp over it raises.
    it 'scrubs invalid UTF-8 rather than raising, and still masks' do
      text = (+"parse failed \xFF\xFE password=#{s1}; attempt=2").force_encoding(Encoding::UTF_8)
      expect(text.valid_encoding?).to be(false)

      filtered = described_class.filter_text(text)

      expect(filtered).to be_valid_encoding
      expect(filtered).not_to include(s1)
      expect(filtered).to end_with("password=#{described_class::MASK}; attempt=2")
    end

    it 'masks Basic and Bearer credentials in an Authorization header' do
      basic  = described_class.filter_text("Authorization: Basic #{s1}")
      bearer = described_class.filter_text(%("authorization"=>"Bearer #{s2}"))

      expect(basic).not_to include(s1)
      expect(bearer).not_to include(s2)
    end

    it 'masks the userinfo of a URL' do
      filtered = described_class.filter_text("connect failed for postgres://admin:#{s1}@db.example/app")

      expect(filtered).not_to include(s1, 'admin')
      expect(filtered).to include('@db.example/app')
    end

    it 'fails closed when the bracket is never closed' do
      filtered = described_class.filter_text(%(boom token: {"a"=>"#{s1}", "b"=>["#{s2}"))

      expect(filtered).not_to include(s1, s2)
      expect(filtered).to start_with('boom token: ')
    end

    it 'fails closed when the quote is never closed' do
      filtered = described_class.filter_text(%(password="#{s1} #{s2}))

      expect(filtered).not_to include(s1, s2)
    end

    it 'fails closed when a bracket is closed by the wrong kind' do
      expect(described_class.filter_text(%(api_key: [#{s1}} #{s2}))).not_to include(s1, s2)
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
