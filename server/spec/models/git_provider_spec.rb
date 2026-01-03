# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GitProvider, type: :model do
  subject(:provider) { build(:git_provider) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:provider_type) }
    it { is_expected.to validate_presence_of(:capabilities) }

    context 'provider_type inclusion' do
      it 'accepts valid provider types' do
        %w[github gitlab gitea].each do |type|
          provider = build(:git_provider, provider_type: type)
          expect(provider).to be_valid
        end
      end

      it 'rejects invalid provider types' do
        provider = build(:git_provider, provider_type: 'invalid')
        expect(provider).not_to be_valid
        expect(provider.errors[:provider_type]).to include('must be github, gitlab, or gitea')
      end
    end

    context 'slug uniqueness' do
      before { create(:git_provider, slug: 'github') }

      it 'validates slug uniqueness' do
        duplicate = build(:git_provider, slug: 'github')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:slug]).to include('has already been taken')
      end
    end
  end

  describe 'associations' do
    it { is_expected.to have_many(:git_provider_credentials).dependent(:destroy) }
    it { is_expected.to have_many(:git_webhook_events).dependent(:destroy) }
  end

  describe 'scopes' do
    let!(:active_provider) { create(:git_provider, is_active: true) }
    let!(:inactive_provider) { create(:git_provider, is_active: false) }
    let!(:github_provider) { create(:git_provider, :github) }
    let!(:gitlab_provider) { create(:git_provider, :gitlab) }
    let!(:ci_cd_provider) { create(:git_provider, :gitea) }

    describe '.active' do
      it 'returns only active providers' do
        expect(described_class.active).to include(active_provider)
        expect(described_class.active).not_to include(inactive_provider)
      end
    end

    describe '.by_type' do
      it 'filters by provider type' do
        expect(described_class.by_type('github')).to include(github_provider)
        expect(described_class.by_type('github')).not_to include(gitlab_provider)
      end
    end

    describe '.with_ci_cd' do
      it 'returns providers with CI/CD support' do
        expect(described_class.with_ci_cd).to include(ci_cd_provider)
      end
    end
  end

  describe 'instance methods' do
    describe '#github?' do
      it 'returns true for github providers' do
        provider = build(:git_provider, :github)
        expect(provider.github?).to be true
      end

      it 'returns false for non-github providers' do
        provider = build(:git_provider, :gitlab)
        expect(provider.github?).to be false
      end
    end

    describe '#gitlab?' do
      it 'returns true for gitlab providers' do
        provider = build(:git_provider, :gitlab)
        expect(provider.gitlab?).to be true
      end
    end

    describe '#gitea?' do
      it 'returns true for gitea providers' do
        provider = build(:git_provider, :gitea)
        expect(provider.gitea?).to be true
      end
    end

    describe '#supports_ci_cd?' do
      it 'returns true when supports_ci_cd is enabled' do
        provider = build(:git_provider, supports_ci_cd: true)
        expect(provider.supports_ci_cd?).to be true
      end

      it 'returns false when supports_ci_cd is disabled' do
        provider = build(:git_provider, supports_ci_cd: false)
        expect(provider.supports_ci_cd?).to be false
      end
    end

    describe '#supports_capability?' do
      let(:provider) { build(:git_provider, capabilities: %w[repos branches webhooks]) }

      it 'returns true when provider has capability' do
        expect(provider.supports_capability?('repos')).to be true
        expect(provider.supports_capability?('webhooks')).to be true
      end

      it 'returns false when provider lacks capability' do
        expect(provider.supports_capability?('ci_cd')).to be false
      end
    end

    describe '#self_hosted?' do
      it 'returns true for gitea providers' do
        provider = build(:git_provider, :gitea)
        expect(provider.self_hosted?).to be true
      end

      it 'returns true for github with custom api_base_url' do
        provider = build(:git_provider, :github, api_base_url: 'https://github.enterprise.com/api/v3')
        expect(provider.self_hosted?).to be true
      end

      it 'returns false for standard github' do
        provider = build(:git_provider, :github, api_base_url: nil)
        expect(provider.self_hosted?).to be false
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates slug from name if not provided' do
        provider = build(:git_provider, name: 'My Git Provider', slug: nil)
        provider.valid?
        expect(provider.slug).to eq('my-git-provider')
      end

      it 'normalizes api_base_url by removing trailing slash' do
        provider = build(:git_provider, api_base_url: 'https://api.example.com/')
        provider.valid?
        expect(provider.api_base_url).to eq('https://api.example.com')
      end

      it 'normalizes web_base_url by removing trailing slash' do
        provider = build(:git_provider, web_base_url: 'https://example.com/')
        provider.valid?
        expect(provider.web_base_url).to eq('https://example.com')
      end
    end
  end
end
