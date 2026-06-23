# frozen_string_literal: true

require 'spec_helper'
require 'active_support/security_utils' # secure_compare (loaded by the full app at runtime)
require_relative '../../../../app/services/devops/git_providers/webhook_normalizer'

RSpec.describe Devops::GitProviders::WebhookNormalizer do
  describe '.normalize dispatch' do
    it 'dispatches to the provider normalizer' do
      result = described_class.normalize(provider_type: :github, event_type: 'push', payload: { 'ref' => 'refs/heads/main' })
      expect(result[:provider]).to eq(:github)
      expect(result[:event]).to eq('push')
    end

    it 'raises ArgumentError for an unknown provider' do
      expect { described_class.normalize(provider_type: :bitbucket, event_type: 'push', payload: {}) }
        .to raise_error(ArgumentError, /Unknown provider type: bitbucket/)
    end
  end

  describe 'event-type normalization' do
    it 'maps native event names to canonical EVENT_* per provider' do
      expect(described_class.normalize(provider_type: :gitea, event_type: 'issues', payload: {})[:event]).to eq('issue')
      expect(described_class.normalize(provider_type: :github, event_type: 'pull_request', payload: {})[:event]).to eq('pull_request')
      expect(described_class.normalize(provider_type: :github, event_type: 'workflow_run', payload: {})[:event]).to eq('workflow_run')
    end

    it "handles GitLab's *_hook naming and push" do
      expect(described_class.normalize(provider_type: :gitlab, event_type: 'push_hook', payload: {})[:event]).to eq('push')
      expect(described_class.normalize(provider_type: :gitlab, event_type: 'merge_request', payload: {})[:event]).to eq('pull_request')
      expect(described_class.normalize(provider_type: :gitlab, event_type: 'note_hook', payload: {})[:event]).to eq('issue_comment')
    end

    it 'passes through an unknown event type unchanged' do
      expect(described_class.normalize(provider_type: :github, event_type: 'star', payload: {})[:event]).to eq('star')
    end
  end

  describe 'push payload normalization' do
    it 'normalizes commits, head_commit, and pusher' do
      payload = {
        'ref' => 'refs/heads/main',
        'before' => 'aaa', 'after' => 'bbb',
        'commits' => [{ 'id' => 'c1', 'message' => 'msg', 'author' => { 'name' => 'Al' }, 'timestamp' => 't0' }],
        'head_commit' => { 'id' => 'c1', 'message' => 'msg' },
        'pusher' => { 'name' => 'Al' }
      }
      result = described_class.normalize(provider_type: :github, event_type: 'push', payload: payload)

      expect(result[:ref]).to eq('refs/heads/main')
      expect(result[:commits]).to eq([{ id: 'c1', message: 'msg', author: 'Al', timestamp: 't0' }])
      expect(result[:head_commit]).to eq({ id: 'c1', message: 'msg' })
      expect(result[:pusher]).to eq({ name: 'Al' })
    end
  end

  describe '.verify_signature' do
    let(:secret) { 's3cr3t' }
    let(:payload) { '{"a":1}' }
    let(:good) { "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}" }

    it 'accepts a correct HMAC-SHA256 for github/gitea' do
      expect(described_class.verify_signature(provider_type: :github, payload: payload, signature: good, secret: secret)).to be(true)
      expect(described_class.verify_signature(provider_type: :gitea, payload: payload, signature: good, secret: secret)).to be(true)
    end

    it 'rejects a wrong signature' do
      expect(described_class.verify_signature(provider_type: :github, payload: payload, signature: 'sha256=deadbeef', secret: secret)).to be(false)
    end

    it 'returns true when the secret is blank (verification skipped) and false when the signature is blank' do
      expect(described_class.verify_signature(provider_type: :github, payload: payload, signature: good, secret: '')).to be(true)
      expect(described_class.verify_signature(provider_type: :github, payload: payload, signature: '', secret: secret)).to be(false)
    end

    it 'compares the token directly for gitlab' do
      expect(described_class.verify_signature(provider_type: :gitlab, payload: payload, signature: secret, secret: secret)).to be(true)
      expect(described_class.verify_signature(provider_type: :gitlab, payload: payload, signature: 'nope', secret: secret)).to be(false)
    end
  end

  describe '.detect_provider / .extract_event_type' do
    it 'detects the provider from headers' do
      expect(described_class.detect_provider('X-Gitea-Event' => 'push')).to eq(:gitea)
      expect(described_class.detect_provider('X-Gitlab-Event' => 'Push Hook')).to eq(:gitlab)
      expect(described_class.detect_provider('X-GitHub-Event' => 'push')).to eq(:github)
      expect(described_class.detect_provider({})).to be_nil
    end

    it 'normalizes the GitLab event header to a bare snake_case name' do
      expect(described_class.extract_event_type(headers: { 'X-Gitlab-Event' => 'Merge Request Hook' }, provider_type: :gitlab)).to eq('merge_request')
    end
  end
end
