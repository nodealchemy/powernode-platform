# frozen_string_literal: true

require 'spec_helper'
require 'active_support/testing/time_helpers'
require_relative '../../app/services/credential_resolver'

RSpec.describe CredentialResolver do
  include ActiveSupport::Testing::TimeHelpers

  let(:api_post) { double('api_post') }
  subject(:resolver) { described_class.new(api_post) }

  describe '#resolve' do
    it 'returns nil for a blank credential id without calling the server' do
      expect(resolver.resolve(nil)).to be_nil
      expect(resolver.resolve('')).to be_nil
    end

    it 'fetches via the decrypt endpoint and returns the credentials hash' do
      allow(api_post).to receive(:call).and_return({ 'credentials' => { 'api_key' => 'sk-1' } })
      expect(resolver.resolve('cred-1')).to eq({ 'api_key' => 'sk-1' })
      expect(api_post).to have_received(:call).with('/api/v1/internal/ai/credentials/cred-1/decrypt', {})
    end

    it 'unwraps a nested data.credentials shape' do
      allow(api_post).to receive(:call).and_return({ 'data' => { 'credentials' => { 'api_key' => 'sk-2' } } })
      expect(resolver.resolve('c')).to eq({ 'api_key' => 'sk-2' })
    end

    it 'returns the whole response when neither credentials nor data is present' do
      allow(api_post).to receive(:call).and_return({ 'api_key' => 'sk-3', 'success' => true })
      expect(resolver.resolve('c')).to eq({ 'api_key' => 'sk-3', 'success' => true })
    end
  end

  describe 'caching' do
    it 'serves from cache within the TTL (one server call)' do
      allow(api_post).to receive(:call).and_return({ 'credentials' => { 'api_key' => 'sk-1' } })
      freeze_time do
        resolver.resolve('c')
        resolver.resolve('c')
      end
      expect(api_post).to have_received(:call).once
    end

    it 're-fetches after the TTL expires (avoids serving a stale/rotated credential)' do
      allow(api_post).to receive(:call).and_return(
        { 'credentials' => { 'api_key' => 'old' } },
        { 'credentials' => { 'api_key' => 'new' } }
      )
      first = resolver.resolve('c')
      travel(CredentialResolver::CACHE_TTL + 1) do
        expect(resolver.resolve('c')).to eq({ 'api_key' => 'new' })
      end
      expect(first).to eq({ 'api_key' => 'old' })
      expect(api_post).to have_received(:call).twice
    end
  end

  describe '#clear_cache' do
    it 'evicts a single credential so the next resolve re-fetches' do
      allow(api_post).to receive(:call).and_return({ 'credentials' => { 'api_key' => 'sk-1' } })
      freeze_time do
        resolver.resolve('c')
        resolver.clear_cache('c')
        resolver.resolve('c')
      end
      expect(api_post).to have_received(:call).twice
    end

    it 'evicts all credentials when called without an id' do
      allow(api_post).to receive(:call).and_return({ 'credentials' => {} })
      freeze_time do
        resolver.resolve('a')
        resolver.resolve('b')
        resolver.clear_cache
        resolver.resolve('a')
        resolver.resolve('b')
      end
      expect(api_post).to have_received(:call).exactly(4).times
    end
  end

  describe 'error handling' do
    it 'raises CredentialError when the server reports failure' do
      allow(api_post).to receive(:call).and_return({ 'success' => false, 'error' => 'boom' })
      expect { resolver.resolve('c') }.to raise_error(CredentialResolver::CredentialError, /boom/)
    end

    it 'raises CredentialError for a non-hash response' do
      allow(api_post).to receive(:call).and_return(nil)
      expect { resolver.resolve('c') }.to raise_error(CredentialResolver::CredentialError, /Unknown error/)
    end
  end
end
