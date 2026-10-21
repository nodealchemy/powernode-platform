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

    describe 'hyphenated and concatenated api key names' do
      let(:fake) { 'abc123fakevalue' }

      it 'masks x-api-key, apikey= and api-key: forms' do
        ['x-api-key: ', 'X-Api-Key: ', 'apikey=', 'api-key: ', 'API-KEY=', '"apikey"=>"'].each do |lead|
          result = described_class.filter_text("#{lead}#{fake}")
          expect(result).to include(described_class::MASK), lead
          expect(result).not_to include(fake), lead
        end
      end

      it 'masks the hash keys api-key and apikey but keeps api_key_name legible' do
        filtered = described_class.filter('api-key' => fake, 'apikey' => fake, 'api_key_name' => 'ci key')

        expect(filtered['api-key']).to eq('[FILTERED]')
        expect(filtered['apikey']).to eq('[FILTERED]')
        expect(filtered['api_key_name']).to eq('ci key')
      end
    end

    describe 'PEM private key blocks' do
      let(:label) { 'PRIVATE' + ' KEY' }
      let(:begin_line) { "-----BEGIN #{label}-----" }
      let(:end_line) { "-----END #{label}-----" }
      let(:body) { %w[FAKEBODYLINEONE1234 FAKEBODYLINETWO5678] }

      it 'masks the whole block' do
        result = described_class.filter_text("before\n#{begin_line}\n#{body.join("\n")}\n#{end_line}\nafter")

        expect(result).not_to include(*body)
        expect(result).to include(described_class::MASK)
        expect(result).to start_with('before').and end_with('after')
      end

      it 'masks typed blocks such as RSA and OPENSSH' do
        %w[RSA OPENSSH EC].each do |type|
          text = "-----BEGIN #{type} #{label}-----\n#{body.first}\n-----END #{type} #{label}-----"
          expect(described_class.filter_text(text)).not_to include(body.first), type
        end
      end

      it 'fails closed to the end of the text when the END line is missing' do
        result = described_class.filter_text("err\n#{begin_line}\n#{body.join("\n")}\ntrailing")

        expect(result).not_to include(*body)
        expect(result).not_to include('trailing')
      end

      it 'leaves no key body prefix when truncation would have cut the block' do
        long = "#{'x' * 100} #{begin_line}\n#{'FAKEKEYBODY' * 100}\n#{end_line}"
        result = described_class.filter_text(long)

        expect(result).not_to include('FAKEKEYBODY')
        expect(result.length).to be <= described_class::TEXT_LIMIT
      end
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

  describe 'secret key spellings (IMP adversarial review r2 #5)' do
    forms = %w[privatekey private-key private_key privateKey PrivateKey signingkey signing-key signing_key signingKey
               seedphrase seed-phrase seed_phrase seedPhrase]

    forms.each do |form|
      it "masks #{form} in filter" do
        expect(described_class.filter(form => 'PLAINTEXT')[form]).to eq('[FILTERED]')
      end

      it "masks #{form} in filter_text" do
        text = described_class.filter_text(%(failed with #{form}=PLAINTEXT-VALUE next))

        expect(text).not_to include('PLAINTEXT-VALUE')
      end
    end
  end

  describe 'PEM material and file-shaped keys (r2 #6)' do
    let(:pem) { "-----BEGIN RSA PRIVATE KEY-----\nABCDEF\n-----END RSA PRIVATE KEY-----" }

    it 'masks a PEM block in any string leaf, whatever its key' do
      filtered = described_class.filter('notes' => "see #{pem} done", 'nested' => [ { 'blob' => pem } ])

      expect(filtered.to_json).not_to include('ABCDEF')
      expect(filtered['notes']).to include('see ').and include(' done')
    end

    %w[ssh_key kubeconfig tls_key pem ssh-key sshkey tls-key tlskey id_rsa privkey client-key-data client_key_data
       private_key_pem key_pem tls_key_pem].each do |key|
      it "masks the #{key} key" do
        expect(described_class.filter(key => 'PLAINTEXT')[key]).to eq('[FILTERED]')
      end
    end

    it 'leaves non-secret strings alone' do
      expect(described_class.filter('name' => 'edge-01')['name']).to eq('edge-01')
    end
  end

  describe 'PEM-named keys without over-masking (r2 M)' do
    %w[groupEmail deepEmbedding keepEmpty timestampEmitted ca_cert_pem certificate_pem public_key_pem cert_pem].each do |key|
      it "leaves #{key} legible" do
        expect(described_class.filter(key => 'value-123')[key]).to eq('value-123')
      end
    end
  end

  describe 'base64-wrapped PEM armor (r2 L)' do
    let(:armored) { Base64.strict_encode64("-----BEGIN OPENSSH PRIVATE KEY-----\nABCDEF\n-----END OPENSSH PRIVATE KEY-----\n") }

    it 'masks a string leaf that decodes to a PRIVATE KEY header' do
      expect(armored).to start_with('LS0tLS1CRUdJTi')
      expect(described_class.filter('blob' => armored)['blob']).to eq('[FILTERED]')
    end

    it 'masks it in filter_text too, and leaves other base64 alone' do
      expect(described_class.filter_text("kube data #{armored} end")).not_to include(armored)
      other = Base64.strict_encode64('just some ordinary bytes' * 4)
      expect(described_class.filter('blob' => other)['blob']).to eq(other)
    end
  end

  describe '.filter_text(truncate: false)' do
    it 'masks secrets but neither truncates nor window-cuts' do
      long = ('lorem ipsum ' * 100).strip
      out = described_class.filter_text("#{long} password=hunter2", truncate: false)

      expect(out).to start_with(long)
      expect(out).not_to include('hunter2')
      expect(out.length).to be > described_class::TEXT_LIMIT
    end
  end

  describe 'case and separator twins of the key-material names (r3 M5-1)' do
    %w[clientKeyData ClientKeyData client-key-data keyPem serverKeyPem hostKeyPem key-pem KeyPEM KEY_PEM
       idRsa id_rsa id-rsa id_ed25519 idEd25519 sshKey SshKey tlsKey privKey].each do |key|
      it "masks #{key} in filter and in filter_text (JSON key form)" do
        expect(described_class.filter(key => 'PLAINTEXT')[key]).to eq('[FILTERED]')
        expect(described_class.filter_text(%({"#{key}": "PLAINTEXT-VALUE", "x": 1}))).not_to include('PLAINTEXT-VALUE')
      end
    end
  end

  describe 'benign siblings of the key-material names (r3 L5-2)' do
    %w[ssh_key_fingerprint ssh_key_type ssh_key_present ssh_key_id has_kubeconfig sshKeyFingerprint].each do |key|
      it "leaves #{key} legible" do
        expect(described_class.filter(key => 'value-123')[key]).to eq('value-123')
      end
    end

    it 'still masks a secret whose name merely ends in a benign-looking word' do
      expect(described_class.filter('approle_secret_id' => 'PLAINTEXT')['approle_secret_id']).to eq('[FILTERED]')
      expect(described_class.filter('ssh_key' => 'PLAINTEXT')['ssh_key']).to eq('[FILTERED]')
    end
  end

  describe 'base64 PEM anywhere (r3 M5-2)' do
    let(:pem) { "-----BEGIN RSA PRIVATE KEY-----\n#{'QUJD' * 40}\n-----END RSA PRIVATE KEY-----\n" }
    let(:b64) { Base64.strict_encode64(pem) }
    let(:wrapped) { Base64.encode64(pem) } # MIME, 60-col lines, newline-separated

    it 'masks a base64 PEM run inside a JSON-string kubeconfig under a non-secret key' do
      doc = %({"clusters":[{"name":"c"}],"users":[{"user":{"data":"#{b64}"}}]})

      masked = described_class.filter('blob' => doc)['blob']

      expect(masked).not_to include(b64[0, 40])
      expect(masked).to include('"clusters"')
    end

    it 'masks a base64 PEM after a leading newline' do
      expect(described_class.filter('blob' => "\n  #{b64}")['blob']).not_to include(b64[0, 40])
    end

    it 'masks the WHOLE wrapped run in filter_text, not just the first line' do
      out = described_class.filter_text("key follows:\n#{wrapped}\nend of key")

      wrapped.lines.each { |line| expect(out).not_to include(line.strip) unless line.strip.empty? }
      expect(out).to include('end of key')
    end

    it 'leaves ordinary base64 alone' do
      other = Base64.strict_encode64('plain bytes ' * 20)
      expect(described_class.filter('blob' => "x #{other} y")['blob']).to eq("x #{other} y")
    end
  end

  describe 'the has_ sibling prefix is anchored (r4 M-1)' do
    %w[hashicorp_ssh_key hashi_vault_tls_key hasura_kubeconfig haskeyKubeconfig HASHICORP_SSH_KEY].each do |key|
      it "masks #{key}: a word that merely starts with has is not a presence flag" do
        expect(described_class.filter(key => 'PLAINTEXT')[key]).to eq('[FILTERED]')
      end
    end

    %w[has_kubeconfig hasKubeconfig has-ssh-key HAS_TLS_KEY HasSshKey has_client_key_data].each do |key|
      it "leaves the presence flag #{key} legible" do
        expect(described_class.filter(key => true)[key]).to be(true)
      end
    end
  end

  describe '_file and _path siblings vouch for the name, not the value (r4 L-2)' do
    it 'masks key material held under a _file or _path key' do
      kube = "users:\n- user:\n    token: x"

      expect(described_class.filter('kubeconfig_file' => kube)['kubeconfig_file']).to eq('[FILTERED]')
      expect(described_class.filter('ssh_key_path' => 'not a path at all')['ssh_key_path']).to eq('[FILTERED]')
      expect(described_class.filter('tls_key_file' => { 'data' => 'x' })['tls_key_file']).to eq('[FILTERED]')
      expect(described_class.filter('privkey_path' => "/etc/key\nAAAA")['privkey_path']).to eq('[FILTERED]')
    end

    { 'kubeconfig_path' => '/etc/kube/config', 'ssh_key_path' => '~/.ssh/id_ed25519',
      'tls_key_file' => './certs/tls.key', 'privkey_path' => 'C:\\keys\\host.pem' }.each do |key, path|
      it "leaves #{key} => #{path} legible" do
        expect(described_class.filter(key => path)[key]).to eq(path)
      end
    end

    it 'keeps the value-independent siblings legible whatever the value' do
      filtered = described_class.filter('ssh_key_fingerprint' => 'SHA256:abc def', 'ssh_key_type' => 'ed25519',
                                        'kubeconfig_present' => true, 'ssh_key_id' => 'k-1')

      expect(filtered).to eq('ssh_key_fingerprint' => 'SHA256:abc def', 'ssh_key_type' => 'ed25519',
                             'kubeconfig_present' => true, 'ssh_key_id' => 'k-1')
    end
  end

  describe 'a configured pattern that is only separators (r4 L-3)' do
    before do
      SiteSetting.create!(key: described_class::SETTING_KEY, setting_type: 'json',
                          value: [ '-', '_', '-_-', 'cvv', 'card--number' ].to_json)
    end

    it 'is ignored rather than masking every key' do
      filtered = described_class.filter('name' => 'edge-01', 'cvv' => '123', 'card_number' => '4111')

      expect(filtered).to eq('name' => 'edge-01', 'cvv' => '[FILTERED]', 'card_number' => '[FILTERED]')
      expect(described_class.filter_text('name=edge-01 region=us')).to eq('name=edge-01 region=us')
    end
  end

  describe 'base64 PEM at any alignment, URL-safe or space-wrapped (r4 M-2)' do
    let(:key_pem) { "-----BEGIN RSA PRIVATE KEY-----\n#{'QUJD' * 40}\n-----END RSA PRIVATE KEY-----\n" }
    let(:cert_pem) { "-----BEGIN CERTIFICATE-----\n#{'TUlJ' * 40}\n-----END CERTIFICATE-----\n" }

    def expect_masked(encoded, wrapper: ->(run) { "data: #{run} end" })
      out = described_class.filter('blob' => wrapper.call(encoded))['blob']
      expect(out).not_to include(encoded[0, 24])
      expect(out).not_to include(encoded[-24..])
      expect(out).to include(described_class::MASK)
      expect(described_class.filter_text(wrapper.call(encoded), truncate: false)).not_to include(encoded[-24..])
    end

    it 'masks an encoded pkcs12 export whose key follows Bag Attributes lines and a certificate' do
      export = "Bag Attributes\n    localKeyID: 01 02 03 04\nsubject=CN = test\nissuer=CN = test\n#{cert_pem}" \
               "Bag Attributes\n    localKeyID: 01 02 03 04\nKey Attributes: <No Attributes>\n#{key_pem}"

      expect(Base64.strict_encode64(export)).not_to start_with('LS0tLS1CRUdJTi')
      expect_masked(Base64.strict_encode64(export))
    end

    it 'masks a cert-then-key bundle at each of the three key-header alignments' do
      alignments = (0..2).map do |pad|
        bundle = "#{cert_pem}#{'#' * pad}\n#{key_pem}"
        expect_masked(Base64.strict_encode64(bundle))
        bundle.index('-----BEGIN RSA') % 3
      end

      expect(alignments.sort).to eq([ 0, 1, 2 ])
    end

    it 'masks a key whose encoding starts one or two bytes before the armor' do
      [ "\n#{key_pem}", "\r\n#{key_pem}" ].each { |text| expect_masked(Base64.strict_encode64(text)) }
    end

    it 'masks a URL-safe run through its -/_ characters after the armor' do
      pem = "-----BEGIN RSA PRIVATE KEY-----\n#{'QUJD' * 10}???>>>~~~\n-----END RSA PRIVATE KEY-----\n"
      encoded = Base64.urlsafe_encode64(pem)

      # The -/_ sit after the armor, so this pins the run's alphabet (the tail
      # past them is masked too), not the URL-safe decode.
      expect(encoded.index(/[-_]/)).to be > encoded.index('LS0tLS1CRUdJTi') + 40
      expect_masked(encoded)
    end

    it 'needs the URL-safe decode when the byte just before the armor encodes to - or _' do
      # 0xFF before "-----" puts 63 in the armor's first quantum: "_y0t..."
      # URL-safe. The standard decode skips the _ and loses the first dashes.
      encoded = Base64.urlsafe_encode64("\xFF".b + key_pem)

      expect(encoded).to start_with('_')
      expect_masked(encoded)
    end

    it 'masks a URL-safe run whose -/_ characters come BEFORE the key armor' do
      # ASCII does encode to 62/63 ("???" is "Pz8/" in the standard alphabet,
      # "Pz8_" URL-safe). The lenient decode drops each - and _, misaligning
      # what follows, and one of the four decode offsets realigns the header.
      encoded = Base64.urlsafe_encode64("#{'???' * 30}\n#{key_pem}")
      armor = described_class::BASE64_PEM_NEEDLES.filter_map { |needle| encoded.index(needle) }.min

      expect(encoded.index(/[-_]/)).to be < armor
      expect_masked(encoded)
    end

    # A needle split by the wrap: "x" * k puts the armor's encoding across the
    # first line break at each common MIME / PEM width.
    { 60 => 35, 64 => 38, 76 => 47 }.each do |width, prefix|
      it "masks a run wrapped at #{width} whose armor needle crosses the wrap" do
        encoded = Base64.strict_encode64(('x' * prefix) + key_pem)
        lines = encoded.scan(/.{1,#{width}}/)
        expect(described_class::BASE64_PEM_NEEDLES.none? { |needle| lines.any? { |l| l.include?(needle) } }).to be(true)

        [ "\n", '\\n', ' ' ].each do |joiner|
          wrapped = lines.join(joiner)
          expect(described_class.filter('blob' => "data: #{wrapped} end")['blob']).to eq("data: #{described_class::MASK} end")
          expect(described_class.filter_text("data: #{wrapped} end", truncate: false)).not_to include(lines.last)
        end
      end
    end

    it 'scans a large prose leaf carrying one encoded certificate in bounded time' do
      certificate = Base64.strict_encode64(cert_pem)
      prose = ('well-known re-entrant x-ray state-of-the-art ' * 50_000)[0, 2 * 1024 * 1024]
      text = "#{prose} #{certificate} end"

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      filtered = described_class.filter('blob' => text)['blob']
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(filtered).to eq(text)
      # About 0.4 s before the scan was anchored on the needle; ~0.01 s after.
      expect(elapsed).to be < 0.1
    end

    it 'masks a space-wrapped run whole' do
      chunks = Base64.strict_encode64(key_pem).scan(/.{1,64}/)
      out = described_class.filter('blob' => "key: #{chunks.join(' ')} end of key")['blob']

      chunks.each { |chunk| expect(out).not_to include(chunk) }
      expect(out).to include('end of key')
    end

    it 'leaves an encoded certificate-only bundle legible at every alignment' do
      (0..2).each do |pad|
        encoded = Base64.strict_encode64("#{'#' * pad}#{cert_pem}")
        expect(described_class.filter('blob' => "x #{encoded} y")['blob']).to eq("x #{encoded} y")
      end
    end
  end
end
