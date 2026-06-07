# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Auth::HmacSigner do
  subject(:signer) { described_class.new }

  let(:secret) { "hmac-shared-secret" }

  def hmac_credential(secret_value: secret, key_id: "primary")
    instance_double(
      Ai::DataSourceCredential,
      decrypted_api_secret: secret_value,
      decrypted_api_key: key_id
    )
  end

  def env(method: "GET", url: "https://api.example.com/v1/items", headers: {})
    { method: method, url: url, headers: headers, query: {}, body: nil }
  end

  # Pull the `created=<int>` value back out of an emitted Signature-Input so we
  # can recompute the expected MAC without depending on wall-clock timing.
  def created_from(signature_input)
    signature_input[/created=(\d+)/, 1].to_i
  end

  describe "#sign! header emission" do
    it "emits RFC 9421 Signature-Input and Signature headers under the default label" do
      request = env

      signer.sign!(request, credential: hmac_credential, config: {})

      expect(request[:headers]).to have_key("Signature-Input")
      expect(request[:headers]).to have_key("Signature")
      expect(request[:headers]["Signature-Input"]).to start_with("sig1=")
      # Signature value is wrapped in colons: label=:<base64>:
      expect(request[:headers]["Signature"]).to match(/\Asig1=:[A-Za-z0-9+\/=]+:\z/)
    end

    it "covers @method and @target-uri by default and labels the alg hmac-sha256" do
      request = env

      signer.sign!(request, credential: hmac_credential, config: {})

      input = request[:headers]["Signature-Input"]
      expect(input).to include('("@method" "@target-uri")')
      expect(input).to include('alg="hmac-sha256"')
    end

    it "advertises the credential's key id via keyid" do
      request = env

      signer.sign!(request, credential: hmac_credential(key_id: "primary"), config: {})

      expect(request[:headers]["Signature-Input"]).to include('keyid="primary"')
    end

    it "lets config override the key id" do
      request = env

      signer.sign!(request, credential: hmac_credential(key_id: "ignored"), config: { "key_id" => "override" })

      expect(request[:headers]["Signature-Input"]).to include('keyid="override"')
    end

    it "honors a custom signature label" do
      request = env

      signer.sign!(request, credential: hmac_credential, config: { "label" => "auth1" })

      expect(request[:headers]["Signature-Input"]).to start_with("auth1=")
      expect(request[:headers]["Signature"]).to start_with("auth1=")
    end
  end

  describe "#sign! cryptographic correctness" do
    it "produces a MAC equal to Security::HttpSignature.base64digest over the RFC 9421 base" do
      request = env(method: "GET", url: "https://api.example.com/v1/items")

      signer.sign!(request, credential: hmac_credential(key_id: "primary"), config: {})

      created = created_from(request[:headers]["Signature-Input"])
      params = %{("@method" "@target-uri");created=#{created};alg="hmac-sha256";keyid="primary"}
      base = [
        %("@method": GET),
        %("@target-uri": https://api.example.com/v1/items),
        %("@signature-params": #{params})
      ].join("\n")
      expected_mac = Security::HttpSignature.base64digest(secret: secret, data: base, algorithm: "sha256")

      expect(request[:headers]["Signature"]).to eq("sig1=:#{expected_mac}:")
    end

    it "verifies against Security::HttpSignature.secure_compare (round-trip)" do
      request = env

      signer.sign!(request, credential: hmac_credential, config: {})

      emitted_mac = request[:headers]["Signature"][/:(.+):/, 1]
      created = created_from(request[:headers]["Signature-Input"])
      params = %{("@method" "@target-uri");created=#{created};alg="hmac-sha256";keyid="primary"}
      base = [
        %("@method": GET),
        %("@target-uri": #{request[:url]}),
        %("@signature-params": #{params})
      ].join("\n")
      recomputed = Security::HttpSignature.base64digest(secret: secret, data: base)

      expect(Security::HttpSignature.secure_compare(emitted_mac, recomputed)).to be(true)
    end

    it "uses the configured digest algorithm (sha512 => hmac-sha512 label)" do
      request = env

      signer.sign!(request, credential: hmac_credential, config: { "algorithm" => "sha512" })

      expect(request[:headers]["Signature-Input"]).to include('alg="hmac-sha512"')
    end
  end

  describe "#sign! with a `date` covered component" do
    it "injects a Date header and covers it in the signature base" do
      request = env

      signer.sign!(request, credential: hmac_credential, config: { "components" => %w[@method @target-uri date] })

      expect(request[:headers]).to have_key("Date")
      expect(request[:headers]["Signature-Input"]).to include('"date"')
    end

    it "signs the same Date value it injects (peer can verify)" do
      request = env

      signer.sign!(request, credential: hmac_credential(key_id: "primary"), config: { "components" => %w[date] })

      date = request[:headers]["Date"]
      created = created_from(request[:headers]["Signature-Input"])
      params = %{("date");created=#{created};alg="hmac-sha256";keyid="primary"}
      base = [%("date": #{date}), %("@signature-params": #{params})].join("\n")
      expected_mac = Security::HttpSignature.base64digest(secret: secret, data: base)

      expect(request[:headers]["Signature"]).to eq("sig1=:#{expected_mac}:")
    end

    it "does not overwrite a Date header the caller already set" do
      preset = "Mon, 01 Jan 2024 00:00:00 GMT"
      request = env(headers: { "Date" => preset })

      signer.sign!(request, credential: hmac_credential, config: { "components" => %w[date] })

      expect(request[:headers]["Date"]).to eq(preset)
    end
  end

  describe "#sign! credential resolution + safety" do
    it "reads the secret from a plain Hash credential (:secret)" do
      request = env

      signer.sign!(request, credential: { secret: secret }, config: {})

      expect(request[:headers]).to have_key("Signature")
    end

    it "reads the secret from a plain Hash credential (:hmac_secret)" do
      request = env

      signer.sign!(request, credential: { hmac_secret: secret }, config: {})

      expect(request[:headers]).to have_key("Signature")
    end

    it "leaves the request unsigned when the secret is missing" do
      request = env
      blank = instance_double(Ai::DataSourceCredential, decrypted_api_secret: nil, decrypted_api_key: nil)

      signer.sign!(request, credential: blank, config: {})

      expect(request[:headers]).not_to have_key("Signature")
      expect(request[:headers]).not_to have_key("Signature-Input")
    end

    it "leaves the request unsigned for a nil credential" do
      request = env

      signer.sign!(request, credential: nil, config: {})

      expect(request[:headers]).to eq({})
    end

    it "omits keyid when neither config nor credential supplies one" do
      request = env

      signer.sign!(request, credential: { secret: secret }, config: {})

      expect(request[:headers]["Signature-Input"]).not_to include("keyid=")
    end
  end
end
