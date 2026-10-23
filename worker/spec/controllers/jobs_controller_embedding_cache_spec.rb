# frozen_string_literal: true

require 'rails_helper'
require 'rack/test'
require 'active_support/testing/time_helpers'

# Production incident: the embedding endpoints built their service from scratch on
# EVERY request (the cache lived on the per-request controller instance), so each
# one called the server's /internal/ai/embedding_config AND
# /internal/ai/credentials/:id/decrypt. ~88 of each in five minutes exhausted the
# server's per-IP API throttle and every worker->server call got 429. The service
# (and with it the resolved config and decrypted credential) is now kept for the
# process, per account, for about five minutes.
RSpec.describe JobsController, 'embedding service cache' do
  include Rack::Test::Methods
  include ActiveSupport::Testing::TimeHelpers

  def app
    described_class
  end

  let(:jwt_secret) { 'test-jobs-controller-secret' }
  let(:valid_token) { JWT.encode({ 'type' => 'worker', 'sub' => 'system', 'aud' => 'worker' }, jwt_secret, 'HS256') }
  let(:secret_key) { 'sk-test-DO-NOT-LEAK-0123456789' }
  let(:config) { { 'data' => { 'provider_type' => 'openai', 'credential_id' => 'cred-1' } } }
  let(:api_client) do
    Class.new do
      attr_accessor :on_get, :on_post

      def get(path) = on_get.call(path)
      def post(path, body = {}) = on_post.call(path, body)
    end.new
  end
  let(:fetches) { Hash.new(0) }
  let(:redis) { instance_double(Redis, get: nil, set: nil) }

  before do
    described_class.reset_embedding_services!
    allow_any_instance_of(described_class).to receive(:jwt_secret_key).and_return(jwt_secret) # rubocop:disable RSpec/AnyInstance
    allow(BackendApiClient).to receive(:new).and_return(api_client)
    api_client.on_get = lambda do |path|
      fetches[path.split('?').first] += 1
      config
    end
    api_client.on_post = lambda do |path, _body|
      fetches[path] += 1
      { 'success' => true, 'credentials' => { 'api_key' => secret_key } }
    end
    allow(Redis).to receive(:new).and_return(redis)
    response = instance_double(HTTParty::Response, body: { 'data' => [ { 'index' => 0, 'embedding' => [ 0.1, 0.2 ] } ] }.to_json)
    allow(HTTParty).to receive(:post).and_return(response)
  end

  after { described_class.reset_embedding_services! }

  def embed(text: 'hello', account_id: 'acct-1')
    header 'Authorization', "Bearer #{valid_token}"
    header 'Content-Type', 'application/json'
    post '/api/v1/embeddings/generate', { text: text, account_id: account_id }.to_json
  end

  def config_calls = fetches['/api/v1/internal/ai/embedding_config']
  def decrypt_calls = fetches['/api/v1/internal/ai/credentials/cred-1/decrypt']

  it 'reads the embedding config and decrypts the credential once across many requests' do
    5.times { |i| embed(text: "text #{i}") }

    expect(last_response.status).to eq(200)
    expect(config_calls).to eq(1)
    expect(decrypt_calls).to eq(1)
  end

  it 'serves the batch endpoint from the same cached service' do
    embed
    header 'Authorization', "Bearer #{valid_token}"
    post '/api/v1/embeddings/batch', { texts: [ 'a' ], account_id: 'acct-1' }.to_json

    expect(config_calls).to eq(1)
    expect(decrypt_calls).to eq(1)
  end

  it 'keeps one service per account' do
    embed(account_id: 'acct-1')
    embed(account_id: 'acct-2')
    embed(account_id: 'acct-1')

    expect(config_calls).to eq(2)
  end

  it 'refreshes after about five minutes' do
    embed
    travel 4.minutes do
      embed
      expect(config_calls).to eq(1)
    end
    travel 6.minutes do
      embed
      expect(config_calls).to eq(2)
      expect(decrypt_calls).to eq(2)
    end
  end

  it 'does not cache a failed config fetch' do
    calls = 0
    api_client.on_get = lambda do |_path|
      calls += 1
      raise 'server down' if calls == 1

      config
    end

    embed
    embed

    expect(calls).to eq(2)
    expect(last_response.status).to eq(200)
  end

  it 'never lets the decrypted key surface through the cached service or its logging' do
    embed
    service = described_class.send(:embedding_services).values.first[:service]

    expect(service.inspect).not_to include(secret_key)
    expect(service.to_s).not_to include(secret_key)
    expect(last_response.body).not_to include(secret_key)
  end
end
