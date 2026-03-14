# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OauthApplication, type: :model do
  describe 'associations' do
    it { should belong_to(:owner).optional }
    it { should have_many(:access_tokens).class_name('Doorkeeper::AccessToken').dependent(:delete_all) }
    it { should have_many(:access_grants).class_name('Doorkeeper::AccessGrant').dependent(:delete_all) }
  end

  describe 'validations' do
    subject { build(:oauth_application) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    # NOTE: status has a default set by before_validation callback on :create,
    # which defeats shoulda-matchers validate_presence_of. Test inclusion manually.
    it 'validates status inclusion' do
      app = build(:oauth_application, status: 'invalid')
      expect(app).not_to be_valid
      expect(app.errors[:status]).to be_present
    end

    it 'allows valid status values' do
      %w[active suspended revoked].each do |s|
        app = build(:oauth_application, status: s)
        expect(app).to be_valid, "Expected '#{s}' to be valid"
      end
    end

    # Note: rate_limit_tier inclusion is tested with a custom test because
    # the before_validation :set_defaults callback on :create converts nil
    # to "standard", which interferes with shoulda-matchers' nil check.
    it 'validates rate_limit_tier is one of the allowed values' do
      app = build(:oauth_application, rate_limit_tier: 'invalid')
      expect(app).not_to be_valid
      expect(app.errors[:rate_limit_tier]).to be_present
    end

    it 'allows valid rate_limit_tier values' do
      %w[standard premium business unlimited].each do |tier|
        app = build(:oauth_application, rate_limit_tier: tier)
        expect(app).to be_valid, "Expected #{tier} to be valid"
      end
    end
  end

  describe 'scopes' do
    let!(:active_app) { create(:oauth_application, :active) }
    let!(:suspended_app) { create(:oauth_application, :suspended) }
    let!(:revoked_app) { create(:oauth_application, :revoked) }
    let!(:trusted_app) { create(:oauth_application, :trusted) }
    let!(:machine_client) { create(:oauth_application, :machine_client) }

    describe '.active' do
      it 'returns only active applications' do
        expect(OauthApplication.active).to include(active_app)
        expect(OauthApplication.active).not_to include(suspended_app, revoked_app)
      end
    end

    describe '.suspended' do
      it 'returns only suspended applications' do
        expect(OauthApplication.suspended).to include(suspended_app)
        expect(OauthApplication.suspended).not_to include(active_app, revoked_app)
      end
    end

    describe '.trusted' do
      it 'returns only trusted applications' do
        expect(OauthApplication.trusted).to include(trusted_app)
        expect(OauthApplication.trusted).not_to include(active_app)
      end
    end

    describe '.machine_clients' do
      it 'returns only machine client applications' do
        expect(OauthApplication.machine_clients).to include(machine_client)
        expect(OauthApplication.machine_clients).not_to include(active_app)
      end
    end
  end

  describe 'instance methods' do
    let(:oauth_app) { create(:oauth_application) }

    describe '#active?' do
      it 'returns true when status is active' do
        oauth_app.status = 'active'
        expect(oauth_app.active?).to be true
      end

      it 'returns false when status is not active' do
        oauth_app.status = 'suspended'
        expect(oauth_app.active?).to be false
      end
    end

    describe '#suspended?' do
      it 'returns true when status is suspended' do
        oauth_app.status = 'suspended'
        expect(oauth_app.suspended?).to be true
      end

      it 'returns false when status is not suspended' do
        oauth_app.status = 'active'
        expect(oauth_app.suspended?).to be false
      end
    end

    describe '#revoked?' do
      it 'returns true when status is revoked' do
        oauth_app.status = 'revoked'
        expect(oauth_app.revoked?).to be true
      end

      it 'returns false when status is not revoked' do
        oauth_app.status = 'active'
        expect(oauth_app.revoked?).to be false
      end
    end

    describe '#suspend!' do
      it 'updates status to suspended' do
        expect { oauth_app.suspend!(reason: 'Abuse detected') }.to change { oauth_app.status }.to('suspended')
      end

      it 'stores suspension reason in metadata' do
        oauth_app.suspend!(reason: 'Abuse detected')
        expect(oauth_app.metadata['suspension_reason']).to eq('Abuse detected')
      end

      it 'revokes all tokens' do
        expect(oauth_app).to receive(:revoke_all_tokens!)
        oauth_app.suspend!
      end
    end

    describe '#activate!' do
      it 'updates status to active' do
        oauth_app.update_columns(status: 'suspended')
        oauth_app.status = 'suspended'
        expect { oauth_app.activate! }.to change { oauth_app.status }.to('active')
      end

      it 'removes suspension metadata' do
        oauth_app.metadata = { 'suspension_reason' => 'Test', 'suspended_at' => Time.current.iso8601 }
        oauth_app.activate!
        expect(oauth_app.metadata).not_to have_key('suspension_reason')
        expect(oauth_app.metadata).not_to have_key('suspended_at')
      end
    end

    describe '#rate_limit' do
      it 'returns 1000 for standard tier' do
        oauth_app.rate_limit_tier = 'standard'
        expect(oauth_app.rate_limit).to eq(1_000)
      end

      it 'returns 5000 for premium tier' do
        oauth_app.rate_limit_tier = 'premium'
        expect(oauth_app.rate_limit).to eq(5_000)
      end

      it 'returns 10000 for business tier' do
        oauth_app.rate_limit_tier = 'business'
        expect(oauth_app.rate_limit).to eq(10_000)
      end

      it 'returns nil for unlimited tier' do
        oauth_app.rate_limit_tier = 'unlimited'
        expect(oauth_app.rate_limit).to be_nil
      end
    end

    describe '#scopes_list' do
      it 'returns array of scopes' do
        oauth_app.scopes = 'read write admin'
        expect(oauth_app.scopes_list).to eq([ 'read', 'write', 'admin' ])
      end

      it 'handles empty scopes' do
        oauth_app.scopes = ''
        expect(oauth_app.scopes_list).to eq([])
      end
    end

    describe '#has_scope?' do
      it 'returns true when scope is included' do
        oauth_app.scopes = 'read write'
        expect(oauth_app.has_scope?('read')).to be true
      end

      it 'returns false when scope is not included' do
        oauth_app.scopes = 'read write'
        expect(oauth_app.has_scope?('admin')).to be false
      end

      it 'accepts symbol argument' do
        oauth_app.scopes = 'read write'
        expect(oauth_app.has_scope?(:read)).to be true
      end
    end
  end

  describe 'callbacks' do
    describe 'set_defaults on create' do
      it 'sets default status to active' do
        app = OauthApplication.new(name: 'Test App', redirect_uri: 'https://example.com')
        app.valid?
        expect(app.status).to eq('active')
      end

      it 'sets default rate_limit_tier to standard' do
        app = OauthApplication.new(name: 'Test App', redirect_uri: 'https://example.com')
        app.valid?
        expect(app.rate_limit_tier).to eq('standard')
      end

      it 'sets default metadata to empty hash' do
        app = OauthApplication.new(name: 'Test App', redirect_uri: 'https://example.com')
        app.valid?
        expect(app.metadata).to eq({})
      end
    end
  end
end
