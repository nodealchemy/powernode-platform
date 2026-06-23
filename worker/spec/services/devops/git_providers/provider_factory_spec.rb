# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../app/services/devops/git_providers/provider_factory'

RSpec.describe Devops::GitProviders::ProviderFactory do
  let(:gitea)  { Devops::GitProviders::GiteaProvider }
  let(:gitlab) { Devops::GitProviders::GitlabProvider }
  let(:github) { Devops::GitProviders::GithubProvider }

  describe '.create' do
    it 'dispatches to the right provider class (symbol or string type)' do
      expect(described_class.create(type: :gitea, api_url: 'https://g.example', access_token: 't')).to be_a(gitea)
      expect(described_class.create(type: :gitlab, api_url: 'https://gl.example', access_token: 't')).to be_a(gitlab)
      expect(described_class.create(type: 'github', api_url: 'https://api.github.com', access_token: 't')).to be_a(github)
    end

    it 'raises ArgumentError listing supported types for an unknown type' do
      expect { described_class.create(type: :bitbucket, api_url: 'u', access_token: 't') }
        .to raise_error(ArgumentError, /Unknown provider type: bitbucket.*Supported: gitea, gitlab, github/)
    end
  end

  describe '.detect_type_from_url' do
    it 'returns :github for a nil url' do
      expect(described_class.detect_type_from_url(nil)).to eq(:github)
    end

    it 'detects by host (case-insensitive)' do
      expect(described_class.detect_type_from_url('https://github.com/o/r')).to eq(:github)
      expect(described_class.detect_type_from_url('HTTPS://GITHUB.COM/o/r')).to eq(:github)
      expect(described_class.detect_type_from_url('https://gitlab.com/o/r')).to eq(:gitlab)
      expect(described_class.detect_type_from_url('https://gitlab.self.example/o/r')).to eq(:gitlab)
      expect(described_class.detect_type_from_url('https://gitea.example.com')).to eq(:gitea)
      expect(described_class.detect_type_from_url('https://forgejo.example.com')).to eq(:gitea)
      expect(described_class.detect_type_from_url('https://codeberg.org/o/r')).to eq(:gitea)
    end

    it 'defaults unknown/self-hosted hosts to :gitea' do
      expect(described_class.detect_type_from_url('https://git.internal.example')).to eq(:gitea)
    end
  end

  describe '.supported? / .supported_types' do
    it 'reports supported types' do
      expect(described_class.supported_types).to eq(%i[gitea gitlab github])
      expect(described_class.supported?(:gitea)).to be(true)
      expect(described_class.supported?('github')).to be(true)
      expect(described_class.supported?(:bitbucket)).to be(false)
    end
  end

  describe '.from_api_data' do
    it 'resolves type from provider_type, then type, then URL detection' do
      expect(described_class.from_api_data({ 'provider_type' => 'gitlab', 'api_url' => 'u', 'access_token' => 't' })).to be_a(gitlab)
      expect(described_class.from_api_data({ 'type' => 'github', 'api_url' => 'u', 'access_token' => 't' })).to be_a(github)
      expect(described_class.from_api_data({ 'api_url' => 'https://gitea.example.com', 'access_token' => 't' })).to be_a(gitea)
    end

    it 'falls back to api_token when access_token is absent' do
      expect(described_class.from_api_data({ 'provider_type' => 'gitea', 'api_url' => 'u', 'api_token' => 't' })).to be_a(gitea)
    end
  end

  describe '.from_record' do
    it 'builds the provider via detected type + decrypted token' do
      rec = Struct.new(:provider_type, :api_url, :decrypted_access_token, keyword_init: true)
                  .new(provider_type: 'gitlab', api_url: 'https://gl.example', decrypted_access_token: 'secret')
      expect(described_class.from_record(rec)).to be_a(gitlab)
    end
  end

  describe 'detect_provider_type (private preference: provider_type -> type -> URL)' do
    it 'prefers provider_type' do
      rec = Struct.new(:provider_type, :type, :api_url, keyword_init: true)
                  .new(provider_type: 'gitlab', type: 'github', api_url: 'https://github.com')
      expect(described_class.send(:detect_provider_type, rec)).to eq(:gitlab)
    end

    it 'uses type when provider_type is absent' do
      rec = Struct.new(:type, :api_url, keyword_init: true).new(type: 'github', api_url: 'https://x')
      expect(described_class.send(:detect_provider_type, rec)).to eq(:github)
    end

    it 'falls back to URL detection when neither is present' do
      rec = Struct.new(:api_url, keyword_init: true).new(api_url: 'https://gitea.example.com')
      expect(described_class.send(:detect_provider_type, rec)).to eq(:gitea)
    end
  end

  describe 'decrypt_token (private preference: decrypted_access_token -> access_token -> api_token)' do
    it 'prefers decrypted_access_token' do
      rec = Struct.new(:decrypted_access_token, keyword_init: true).new(decrypted_access_token: 'dec')
      expect(described_class.send(:decrypt_token, rec)).to eq('dec')
    end

    it 'uses access_token next' do
      rec = Struct.new(:access_token, keyword_init: true).new(access_token: 'acc')
      expect(described_class.send(:decrypt_token, rec)).to eq('acc')
    end

    it 'uses api_token last' do
      rec = Struct.new(:api_token, keyword_init: true).new(api_token: 'api')
      expect(described_class.send(:decrypt_token, rec)).to eq('api')
    end

    it 'raises when the record exposes no token accessor' do
      rec = Struct.new(:api_url, keyword_init: true).new(api_url: 'u')
      expect { described_class.send(:decrypt_token, rec) }
        .to raise_error(ArgumentError, /must have access_token or api_token/)
    end
  end
end
