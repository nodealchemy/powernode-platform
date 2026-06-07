# frozen_string_literal: true

require "rails_helper"
require "aws-sigv4"

RSpec.describe Ai::DataSources::Auth::Sigv4Signer do
  subject(:signer) { described_class.new }

  # A credential exposing the decrypted accessors the signer reads. We pass test
  # values directly; no real AWS account is involved (aws-sigv4 is pure Ruby and
  # makes no network calls).
  def aws_credential(key: "AKIAEXAMPLE", secret: "wJalrXUtnFEMI/EXAMPLEKEY")
    instance_double(
      Ai::DataSourceCredential,
      decrypted_api_key: key,
      decrypted_api_secret: secret
    )
  end

  def env(method: "GET", url: "https://api.execute-api.us-east-1.amazonaws.com/prod/items")
    { method: method, url: url, headers: {}, query: {}, body: nil }
  end

  let(:config) { { "region" => "us-east-1", "service" => "execute-api" } }

  describe "#sign! against a request-env Hash" do
    it "wraps Aws::Sigv4::Signer and applies its returned Authorization header" do
      request = env

      signer.sign!(request, credential: aws_credential, config: config)

      expect(request[:headers]).to have_key("authorization")
      expect(request[:headers]["authorization"]).to start_with("AWS4-HMAC-SHA256")
    end

    it "applies the SDK's x-amz-date and content-sha256 headers verbatim" do
      request = env

      signer.sign!(request, credential: aws_credential, config: config)

      header_names = request[:headers].keys.map(&:downcase)
      expect(header_names).to include("x-amz-date")
      expect(header_names).to include("x-amz-content-sha256")
    end

    it "constructs the SDK signer with the region/service from config and creds from the credential" do
      fake_headers = double(headers: { "authorization" => "AWS4-HMAC-SHA256 ..." })
      fake_signer = instance_double(Aws::Sigv4::Signer, sign_request: fake_headers)

      expect(Aws::Sigv4::Signer).to receive(:new).with(
        hash_including(
          service: "execute-api",
          region: "us-east-1",
          access_key_id: "AKIAEXAMPLE",
          secret_access_key: "wJalrXUtnFEMI/EXAMPLEKEY"
        )
      ).and_return(fake_signer)

      signer.sign!(env, credential: aws_credential, config: config)
    end

    it "defaults the service to execute-api when config omits it" do
      expect(Aws::Sigv4::Signer).to receive(:new)
        .with(hash_including(service: "execute-api"))
        .and_call_original

      signer.sign!(env, credential: aws_credential, config: { "region" => "us-east-1" })
    end

    it "canonicalizes the request method/url/body (passes them to sign_request)" do
      fake_signer = instance_double(Aws::Sigv4::Signer)
      allow(Aws::Sigv4::Signer).to receive(:new).and_return(fake_signer)

      expect(fake_signer).to receive(:sign_request).with(
        hash_including(
          http_method: "POST",
          url: "https://api.execute-api.us-east-1.amazonaws.com/prod/items",
          body: '{"x":1}'
        )
      ).and_return(double(headers: {}))

      request = env(method: "POST")
      request[:body] = '{"x":1}'
      signer.sign!(request, credential: aws_credential, config: config)
    end

    it "accepts a plain Hash credential (access_key_id/secret_access_key)" do
      request = env

      signer.sign!(
        request,
        credential: { access_key_id: "AKIAHASH", secret_access_key: "hashsecret" },
        config: config
      )

      expect(request[:headers]).to have_key("authorization")
    end

    it "passes a session token from config through to the SDK signer" do
      expect(Aws::Sigv4::Signer).to receive(:new)
        .with(hash_including(session_token: "tok-123"))
        .and_call_original

      signer.sign!(env, credential: aws_credential, config: config.merge("session_token" => "tok-123"))
    end
  end

  describe "#sign! safety / skip paths" do
    it "leaves the request unsigned when credentials are missing" do
      request = env
      blank_cred = instance_double(
        Ai::DataSourceCredential, decrypted_api_key: nil, decrypted_api_secret: nil
      )

      signer.sign!(request, credential: blank_cred, config: config)

      expect(request[:headers]).to eq({})
    end

    it "leaves the request unsigned when the region is missing from auth_config" do
      request = env

      signer.sign!(request, credential: aws_credential, config: { "service" => "execute-api" })

      expect(request[:headers]).to eq({})
    end

    it "skips a bare Faraday::Connection (SigV4 must be per-request, not per-connection)" do
      conn = Faraday.new(url: "https://api.example.com")

      expect(Aws::Sigv4::Signer).not_to receive(:new)
      expect { signer.sign!(conn, credential: aws_credential, config: config) }.not_to raise_error
      expect(conn.headers).not_to have_key("authorization")
    end

    it "tolerates a nil config without raising" do
      request = env

      expect { signer.sign!(request, credential: aws_credential, config: nil) }.not_to raise_error
      # region is absent => unsigned
      expect(request[:headers]).to eq({})
    end
  end
end
