# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::Docker::RegistryService do
  let(:service) { described_class.new }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:github_provider) { create(:git_provider, provider_type: "github") }
  let(:gitlab_provider) { create(:git_provider, provider_type: "gitlab", web_base_url: "https://gitlab.com") }
  let(:gitea_provider) { create(:git_provider, provider_type: "gitea", web_base_url: "https://gitea.example.com") }

  let(:github_credential) do
    create(:git_provider_credential,
      name: "GitHub",
      provider: github_provider,
      account: account,
      user: user
    )
  end

  let(:gitlab_credential) do
    create(:git_provider_credential,
      name: "GitLab",
      provider: gitlab_provider,
      account: account,
      user: user
    )
  end

  let(:gitea_credential) do
    create(:git_provider_credential,
      name: "Gitea",
      provider: gitea_provider,
      account: account,
      user: user
    )
  end

  describe '#registry_url_for' do
    it 'returns ghcr.io for GitHub' do
      expect(service.registry_url_for(github_credential)).to eq("ghcr.io")
    end

    it 'returns registry.gitlab.com for GitLab (cloud)' do
      expect(service.registry_url_for(gitlab_credential)).to eq("registry.gitlab.com")
    end

    it 'returns host:5050 for self-hosted GitLab' do
      self_hosted_gitlab = create(:git_provider,
        provider_type: "gitlab",
        api_base_url: "https://gitlab.mycompany.com/api/v4",
        web_base_url: "https://gitlab.mycompany.com"
      )
      credential = create(:git_provider_credential,
        name: "Self-hosted GitLab",
        provider: self_hosted_gitlab,
        account: account,
        user: user
      )

      expect(service.registry_url_for(credential)).to eq("gitlab.mycompany.com:5050")
    end

    it 'returns effective_web_base_url for Gitea' do
      expect(service.registry_url_for(gitea_credential)).to eq("https://gitea.example.com")
    end

    it 'returns nil for unsupported providers' do
      bitbucket_provider = create(:git_provider, provider_type: "bitbucket")
      credential = create(:git_provider_credential,
        name: "Bitbucket",
        provider: bitbucket_provider,
        account: account,
        user: user
      )

      expect(service.registry_url_for(credential)).to be_nil
    end
  end

  describe '#docker_auth_config' do
    it 'generates Base64 encoded JSON with auth section for GitHub' do
      result = service.docker_auth_config(github_credential)

      decoded_json = JSON.parse(Base64.strict_decode64(result))
      expect(decoded_json).to have_key("auths")
      expect(decoded_json["auths"]).to have_key("ghcr.io")

      auth_value = decoded_json["auths"]["ghcr.io"]["auth"]
      decoded_auth = Base64.strict_decode64(auth_value)
      # Username comes from credentials hash or defaults
      expect(decoded_auth).to include(":test_token_123")
    end

    it 'uses oauth2 as username for GitLab' do
      result = service.docker_auth_config(gitlab_credential)

      decoded_json = JSON.parse(Base64.strict_decode64(result))
      auth_value = decoded_json["auths"]["registry.gitlab.com"]["auth"]
      decoded_auth = Base64.strict_decode64(auth_value)
      expect(decoded_auth).to start_with("oauth2:")
    end

    it 'returns nil when no registry URL available' do
      bitbucket_provider = create(:git_provider, provider_type: "bitbucket")
      credential = create(:git_provider_credential,
        name: "Bitbucket",
        provider: bitbucket_provider,
        account: account,
        user: user
      )

      expect(service.docker_auth_config(credential)).to be_nil
    end
  end

  describe '#available_registries' do
    it 'returns list of registries from account credentials' do
      github_credential
      gitlab_credential

      registries = service.available_registries(account)

      expect(registries.length).to eq(2)
      expect(registries.map { |r| r[:registry_url] }).to include("ghcr.io", "registry.gitlab.com")
    end

    it 'excludes credentials without registry URLs' do
      bitbucket_provider = create(:git_provider, provider_type: "bitbucket")
      create(:git_provider_credential,
        name: "Bitbucket",
        provider: bitbucket_provider,
        account: account,
        user: user
      )

      registries = service.available_registries(account)

      expect(registries.none? { |r| r[:provider_type] == "bitbucket" }).to be true
    end

    it 'includes credential metadata' do
      github_credential

      registries = service.available_registries(account)

      registry = registries.first
      expect(registry).to include(
        credential_id: github_credential.id,
        credential_name: "GitHub",
        provider_type: "github",
        registry_url: "ghcr.io"
      )
    end
  end
end
