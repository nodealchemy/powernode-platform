require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:user_roles).dependent(:destroy) }
    it { should have_many(:roles).through(:user_roles) }
    it { should have_many(:audit_logs).dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value('user@example.com').for(:email) }
    it { should_not allow_value('invalid_email').for(:email) }

    it { should validate_presence_of(:first_name) }
    it { should validate_length_of(:first_name).is_at_least(1).is_at_most(50) }

    it { should validate_presence_of(:last_name) }
    it { should validate_length_of(:last_name).is_at_least(1).is_at_most(50) }

    it { should validate_presence_of(:role) }
    it { should validate_inclusion_of(:role).in_array(%w[owner admin member]) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive suspended]) }
  end

  describe 'scopes' do
    let!(:account) { create(:account) }
    let!(:active_user) { create(:user, status: 'active') }
    let!(:inactive_user) { create(:user, status: 'inactive') }
    # Create owner first in the account
    let!(:owner) { create(:user, account: account, role: 'owner') }
    # Create other users in the same account, they won't become owners due to the callback logic
    let!(:admin) { User.create!(account: account, email: 'admin@example.com', first_name: 'Admin', last_name: 'User', password: 'SecureFactoryCode$9!', role: 'admin', status: 'active', email_verified_at: 1.day.ago) }
    let!(:member) { User.create!(account: account, email: 'member@example.com', first_name: 'Member', last_name: 'User', password: 'SecureFactoryCode$9!', role: 'member', status: 'active', email_verified_at: 1.day.ago) }
    let!(:verified_user) { create(:user, email_verified_at: 1.day.ago) }
    let!(:unverified_user) { create(:user, email_verified_at: nil) }

    describe '.active' do
      it 'returns only active users' do
        expect(User.active).to include(active_user)
        expect(User.active).not_to include(inactive_user)
      end
    end

    describe '.owners' do
      it 'returns only owner users' do
        expect(User.owners).to include(owner)
        expect(User.owners).not_to include(admin, member)
      end
    end

    describe '.admins' do
      it 'returns only admin users' do
        expect(User.admins).to include(admin)
        expect(User.admins).not_to include(owner, member)
      end
    end

    describe '.members' do
      it 'returns only member users' do
        expect(User.members).to include(member)
        expect(User.members).not_to include(owner, admin)
      end
    end

    describe '.verified' do
      it 'returns only verified users' do
        expect(User.verified).to include(verified_user)
        expect(User.verified).not_to include(unverified_user)
      end
    end

    describe '.unverified' do
      it 'returns only unverified users' do
        expect(User.unverified).to include(unverified_user)
        expect(User.unverified).not_to include(verified_user)
      end
    end
  end

  describe 'callbacks' do
    describe 'normalize_email' do
      it 'downcases and strips email' do
        user = build(:user, email: '  USER@EXAMPLE.COM  ')
        user.valid?
        expect(user.email).to eq('user@example.com')
      end
    end

    describe 'set_owner_if_first_user' do
      let(:account) { create(:account) }

      it 'sets role to owner for first user in account' do
        user = build(:user, account: account, role: 'member')
        user.save
        expect(user.role).to eq('owner')
      end

      it 'does not change role for subsequent users' do
        create(:user, account: account, role: 'owner')
        user = build(:user, account: account, role: 'member')
        user.save
        expect(user.role).to eq('member')
      end
    end
  end

  describe 'instance methods' do
    let(:user) { create(:user, first_name: 'John', last_name: 'Doe') }

    describe '#full_name' do
      it 'returns concatenated first and last name' do
        expect(user.full_name).to eq('John Doe')
      end
    end

    describe '#initials' do
      it 'returns capitalized first letters' do
        expect(user.initials).to eq('JD')
      end
    end

    describe '#active?' do
      it 'returns true for active users' do
        user.status = 'active'
        expect(user.active?).to be true
      end

      it 'returns false for inactive users' do
        user.status = 'inactive'
        expect(user.active?).to be false
      end
    end

    describe 'role predicates' do
      it '#owner? returns true for owner role' do
        user.role = 'owner'
        expect(user.owner?).to be true
      end

      it '#admin? returns true for admin role' do
        user.role = 'admin'
        expect(user.admin?).to be true
      end

      it '#member? returns true for member role' do
        user.role = 'member'
        expect(user.member?).to be true
      end
    end

    describe '#email_verified?' do
      it 'returns true when email_verified_at is present' do
        user.email_verified_at = 1.day.ago
        expect(user.email_verified?).to be true
      end

      it 'returns false when email_verified_at is nil' do
        user.email_verified_at = nil
        expect(user.email_verified?).to be false
      end
    end

    describe '#verify_email!' do
      it 'sets email_verified_at to current time' do
        user.email_verified_at = nil
        expect { user.verify_email! }.to change { user.email_verified_at }.from(nil).to(be_within(1.second).of(Time.current))
      end
    end

    describe '#record_login!' do
      it 'updates last_login_at to current time' do
        expect { user.record_login! }.to change { user.last_login_at }.to(be_within(1.second).of(Time.current))
      end
    end

    describe '#has_role?' do
      let(:role) { create(:role, name: 'Custom Role') }

      before { user.roles << role }

      it 'returns true when user has the role' do
        expect(user.has_role?('Custom Role')).to be true
      end

      it 'returns false when user does not have the role' do
        expect(user.has_role?('Other Role')).to be false
      end
    end

    describe '#has_permission?' do
      let(:permission) { create(:permission, resource: 'accounts', action: 'read') }
      let(:role) { create(:role) }

      before do
        role.permissions << permission
        user.roles << role
      end

      it 'returns true when user has permission through role' do
        expect(user.has_permission?('accounts.read')).to be true
      end

      it 'returns false when user does not have permission' do
        expect(user.has_permission?('accounts.delete')).to be false
      end
    end

    describe '#can?' do
      let!(:admin_account) { create(:account) }
      let!(:owner) { create(:user, account: admin_account, role: 'owner') }
      let(:user) { create(:user, account: admin_account, role: 'admin', status: 'active') }

      describe 'analytics permissions' do
        it 'allows admins to view analytics' do
          expect(user.can?(:view_analytics)).to be true
        end

        it 'allows admins to export analytics' do
          expect(user.can?(:export_analytics)).to be true
        end

        it 'only allows owners to view global analytics' do
          expect(user.can?(:view_global_analytics)).to be false

          user.role = 'owner'
          expect(user.can?(:view_global_analytics)).to be true
        end
      end
    end
  end

  describe 'password authentication' do
    let(:user) { create(:user, password: 'UltraSecureP@ssw0rd9x2!') }

    it 'authenticates with correct password' do
      expect(user.authenticate('UltraSecureP@ssw0rd9x2!')).to eq(user)
    end

    it 'returns false with incorrect password' do
      expect(user.authenticate('wrongpassword')).to be false
    end
  end
end
