# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:audit_logs).dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value('user@example.com').for(:email) }
    it { should_not allow_value('invalid_email').for(:email) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_least(1).is_at_most(100) }


    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive suspended]) }
  end

  describe 'scopes' do
    let!(:account) { create(:account) }
    let!(:active_user) { create(:user, status: 'active') }
    let!(:inactive_user) { create(:user, status: 'inactive') }
    # Create owner first in the account
    let!(:owner) { create(:user, :owner, account: account) }
    # Create other users in the same account with specific roles
    let!(:admin) { create(:user, :admin, account: account, email: 'admin@example.com') }
    let!(:member) { create(:user, :member, account: account, email: 'member@example.com') }
    let!(:verified_user) { create(:user, email_verified_at: 1.day.ago) }
    let!(:unverified_user) { create(:user, email_verified_at: nil) }

    describe '.active' do
      it 'returns only active users' do
        expect(User.active).to include(active_user)
        expect(User.active).not_to include(inactive_user)
      end
    end

    describe '.with_role' do
      it 'returns users with owner role' do
        expect(User.with_role('owner')).to include(owner)
        expect(User.with_role('owner')).not_to include(admin, member)
      end

      it 'returns users with admin role' do
        expect(User.with_role('admin')).to include(admin)
        expect(User.with_role('admin')).not_to include(owner, member)
      end

      it 'returns users with member role' do
        expect(User.with_role('member')).to include(member)
        expect(User.with_role('member')).not_to include(owner, admin)
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

      it 'assigns owner role to first user in account' do
        user = build(:user, account: account)
        user.save
        expect(user.has_role?('owner')).to be true
      end

      it 'assigns member role to subsequent users' do
        # Create first user (will be owner)
        first_user = create(:user, account: account)

        # Create second user (should be member)
        second_user = build(:user, account: account)
        second_user.save
        expect(second_user.has_role?('member')).to be true
        expect(second_user.has_role?('owner')).to be false
      end
    end
  end

  describe 'instance methods' do
    let(:user) { create(:user, name: 'John Doe') }

    describe '#full_name' do
      it 'returns the name field' do
        expect(user.full_name).to eq('John Doe')
      end
    end

    describe '#initials' do
      it 'returns capitalized first letters' do
        expect(user.initials).to eq('JD')
      end

      context 'with single name' do
        let(:single_name_user) { create(:user, name: 'John') }

        it 'returns single initial' do
          expect(single_name_user.initials).to eq('J')
        end
      end

      context 'with empty name' do
        let(:empty_name_user) { build(:user, name: '') }

        it 'returns empty string' do
          expect(empty_name_user.initials).to eq('')
        end
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
        user_with_owner_role = create(:user, :owner)
        expect(user_with_owner_role.owner?).to be true
      end

      it '#admin? returns true for admin role' do
        # Create account with owner first, then create admin user
        account = create(:account)
        create(:user, :owner, account: account) # This will be the owner
        user_with_admin_role = create(:user, :admin, account: account)
        expect(user_with_admin_role.admin?).to be true
      end

      it '#member? returns true for member role' do
        # Create account with owner first, then create member user
        account = create(:account)
        create(:user, :owner, account: account) # This will be the owner
        user_with_member_role = create(:user, :member, account: account)
        expect(user_with_member_role.member?).to be true
      end
    end

    describe '#verified?' do
      it 'returns true when email_verified_at is present' do
        user.email_verified_at = 1.day.ago
        expect(user.verified?).to be true
      end

      it 'returns false when email_verified_at is nil' do
        user.email_verified_at = nil
        expect(user.verified?).to be false
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
      it 'returns true when user has the role' do
        user.add_role('manager')
        expect(user.has_role?('manager')).to be true
      end

      it 'returns false when user does not have the role' do
        user.add_role('member')
        expect(user.has_role?('manager')).to be false
      end
    end

    describe '#has_permission?' do
      before do
        user.add_role('manager')  # Manager role has team permissions
      end

      it 'returns true when user has permission through role' do
        expect(user.has_permission?('team.invite')).to be true
      end

      it 'returns false when user does not have permission' do
        expect(user.has_permission?('system.admin')).to be false
      end
    end

    describe '#can?' do
      let!(:admin_account) { create(:account) }
      let!(:owner) { create(:user, :owner, account: admin_account) }
      let(:user) { create(:user, :admin, account: admin_account, status: 'active') }

      describe 'analytics permissions' do
        it 'allows admins to view analytics' do
          expect(user.can?('ai.analytics.read')).to be true
        end

        it 'allows admins to export analytics' do
          expect(user.can?('ai.analytics.export')).to be true
        end

        it 'allows owners to view analytics' do
          expect(owner.can?('ai.analytics.read')).to be true
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

  # IMP-99e8e4701150 — pending vs confirmed enrolment, backup-code digests.
  describe 'two-factor authentication' do
    let(:user) { create(:user) }

    def totp_for(secret)
      ROTP::TOTP.new(secret).now
    end

    describe '#two_factor_enabled?' do
      it 'is false while only a pending secret exists' do
        user.start_two_factor_setup!

        expect(user.two_factor_enabled?).to be false
      end

      it 'is true only after confirmation' do
        secret = user.start_two_factor_setup!
        user.confirm_two_factor_setup!(totp_for(secret))

        expect(user.two_factor_enabled?).to be true
      end
    end

    describe '#start_two_factor_setup!' do
      it 'stores a pending secret with a future expiry and does not touch the confirmed secret' do
        user.start_two_factor_setup!

        expect(user.two_factor_pending?).to be true
        expect(user.two_factor_pending_expires_at).to be > Time.current
        expect(user.two_factor_secret).to be_nil
      end

      it 'replaces the pending secret when called again' do
        first_secret = user.start_two_factor_setup!
        second_secret = user.start_two_factor_setup!

        expect(second_secret).not_to eq(first_secret)
        expect(user.two_factor_pending_secret).to eq(second_secret)
      end
    end

    describe '#two_factor_pending_expired?' do
      it 'is true once the TTL has passed' do
        user.start_two_factor_setup!
        user.update_column(:two_factor_pending_expires_at, 1.second.ago)

        expect(user.two_factor_pending_expired?).to be true
        expect(user.two_factor_pending?).to be false
      end
    end

    describe '#confirm_two_factor_setup!' do
      it 'activates 2FA, mints backup codes, and clears the pending fields' do
        secret = user.start_two_factor_setup!

        codes = user.confirm_two_factor_setup!(totp_for(secret))

        expect(codes).to be_an(Array)
        expect(codes).not_to be_empty
        expect(user.two_factor_secret).to eq(secret)
        expect(user.two_factor_enabled_at).to be_present
        expect(user.two_factor_pending_secret).to be_nil
        expect(user.two_factor_pending_expires_at).to be_nil
      end

      it 'persists only bcrypt digests of the backup codes, never the plaintext' do
        secret = user.start_two_factor_setup!
        codes = user.confirm_two_factor_setup!(totp_for(secret))

        expect(user.backup_codes & codes).to be_empty
        expect(user.backup_codes).to all(match(/\A\$2[aby]?\$/))
      end

      it 'returns false without a pending secret' do
        expect(user.confirm_two_factor_setup!('123456')).to be false
      end

      it 'returns false for an invalid token' do
        user.start_two_factor_setup!

        expect(user.confirm_two_factor_setup!('000000')).to be false
        expect(user.two_factor_enabled?).to be false
      end

      it 'returns false once the pending secret has expired' do
        secret = user.start_two_factor_setup!
        user.update_column(:two_factor_pending_expires_at, 1.second.ago)

        expect(user.confirm_two_factor_setup!(totp_for(secret))).to be false
      end

      # IMP-99e8e4701150 review M2: a second confirm racing (or simply
      # following) a first successful one must not re-mint a fresh set of
      # backup codes — the pending fields are already cleared by the first
      # call, so #two_factor_pending? is false for the second.
      it 'is idempotent: a second confirm with the same token cannot re-mint codes' do
        secret = user.start_two_factor_setup!
        token = totp_for(secret)
        first_codes = user.confirm_two_factor_setup!(token)
        stored_digests = user.reload.backup_codes

        second_result = user.confirm_two_factor_setup!(token)

        expect(second_result).to be false
        expect(first_codes).to be_an(Array)
        expect(user.reload.backup_codes).to eq(stored_digests)
      end

      it 'runs under a row lock (with_lock), re-checking pending state inside it' do
        secret = user.start_two_factor_setup!

        expect(user).to receive(:with_lock).and_call_original
        user.confirm_two_factor_setup!(totp_for(secret))
      end
    end

    describe '#verify_backup_code' do
      before do
        secret = user.start_two_factor_setup!
        @codes = user.confirm_two_factor_setup!(totp_for(secret))
      end

      it 'verifies a valid, unused code and consumes it' do
        code = @codes.first

        expect(user.verify_backup_code(code)).to be true
        expect(user.reload.two_factor_backup_codes_count).to eq(@codes.size - 1)
      end

      it 'rejects a code that has already been used' do
        code = @codes.first
        user.verify_backup_code(code)

        expect(user.verify_backup_code(code)).to be false
      end

      it 'rejects an unknown code' do
        expect(user.verify_backup_code('NOTREAL1')).to be false
      end

      it 'runs under a row lock (with_lock), re-checking the stored codes inside it' do
        expect(user).to receive(:with_lock).and_call_original
        user.verify_backup_code(@codes.first)
      end
    end

    describe '#regenerate_backup_codes!' do
      it 'invalidates every previously issued code' do
        secret = user.start_two_factor_setup!
        old_codes = user.confirm_two_factor_setup!(totp_for(secret))

        user.regenerate_backup_codes!

        old_codes.each do |code|
          expect(user.verify_backup_code(code)).to be false
        end
      end

      it 'runs under a row lock (with_lock)' do
        secret = user.start_two_factor_setup!
        user.confirm_two_factor_setup!(totp_for(secret))

        expect(user).to receive(:with_lock).and_call_original
        user.regenerate_backup_codes!
      end
    end

    describe '#disable_two_factor!' do
      it 'clears the confirmed secret, backup codes, and any pending state' do
        secret = user.start_two_factor_setup!
        user.confirm_two_factor_setup!(totp_for(secret))

        user.disable_two_factor!

        expect(user.two_factor_enabled?).to be false
        expect(user.two_factor_secret).to be_nil
        expect(user.backup_codes).to be_nil
        expect(user.two_factor_pending_secret).to be_nil
      end
    end
  end
end
