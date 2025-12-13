# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invitation, type: :model do
  let(:account) { create(:account) }
  let(:inviter) { create(:user, :manager, account: account) }

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:inviter).class_name('User') }
  end

  describe 'validations' do
    subject { build(:invitation, account: account, inviter: inviter) }

    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:status) }
    # Token and expires_at are auto-generated, so we test them differently
    it 'requires token for update' do
      invitation = create(:invitation, account: account, inviter: inviter)
      invitation.token = nil
      expect(invitation).not_to be_valid
    end

    it 'requires expires_at for update' do
      invitation = create(:invitation, account: account, inviter: inviter)
      invitation.expires_at = nil
      expect(invitation).not_to be_valid
    end
    it { should validate_presence_of(:first_name) }
    it { should validate_presence_of(:last_name) }

    it 'validates email format' do
      invitation = build(:invitation, account: account, inviter: inviter, email: 'invalid')
      expect(invitation).not_to be_valid
      expect(invitation.errors[:email]).to include('is invalid')
    end

    it 'validates email uniqueness scoped to account' do
      create(:invitation, account: account, inviter: inviter, email: 'test@example.com')
      duplicate = build(:invitation, account: account, inviter: inviter, email: 'test@example.com')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been invited to this account')
    end

    it 'allows same email in different accounts' do
      other_account = create(:account)
      create(:invitation, account: account, inviter: inviter, email: 'test@example.com')
      duplicate = build(:invitation, account: other_account, inviter: inviter, email: 'test@example.com')

      expect(duplicate).to be_valid
    end

    it 'validates status inclusion' do
      invitation = build(:invitation, account: account, inviter: inviter)
      invitation.status = 'invalid'
      expect(invitation).not_to be_valid
      expect(invitation.errors[:status]).to include('is not included in the list')
    end

    it 'validates token uniqueness' do
      token = SecureRandom.urlsafe_base64(32)
      create(:invitation, account: account, inviter: inviter, token: token)
      duplicate = build(:invitation, account: account, inviter: inviter, token: token)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:pending_invitation) { create(:invitation, account: account, inviter: inviter) }
    let!(:expired_invitation) { create(:invitation, :expired, account: account, inviter: inviter) }
    let!(:accepted_invitation) { create(:invitation, :accepted, account: account, inviter: inviter) }

    describe '.pending' do
      it 'returns only pending invitations' do
        expect(Invitation.pending).to include(pending_invitation)
        expect(Invitation.pending).not_to include(accepted_invitation)
      end
    end

    describe '.expired' do
      it 'returns only expired invitations' do
        expect(Invitation.expired).to include(expired_invitation)
        expect(Invitation.expired).not_to include(pending_invitation)
      end
    end

    describe '.active' do
      it 'returns pending and not expired invitations' do
        expect(Invitation.active).to include(pending_invitation)
        expect(Invitation.active).not_to include(expired_invitation)
        expect(Invitation.active).not_to include(accepted_invitation)
      end
    end
  end

  describe 'callbacks' do
    describe 'token generation' do
      it 'generates token on create if blank' do
        invitation = build(:invitation, account: account, inviter: inviter, token: nil)
        invitation.save

        expect(invitation.token).to be_present
        expect(invitation.token.length).to be >= 32
      end

      it 'does not override existing token' do
        token = 'existing-token'
        invitation = create(:invitation, account: account, inviter: inviter, token: token)

        expect(invitation.token).to eq(token)
      end
    end

    describe 'expiration setting' do
      it 'sets expiration to 7 days from now if blank' do
        invitation = build(:invitation, account: account, inviter: inviter, expires_at: nil)
        invitation.save

        expect(invitation.expires_at).to be_within(1.second).of(7.days.from_now)
      end

      it 'does not override existing expiration' do
        expiration = 30.days.from_now
        invitation = create(:invitation, account: account, inviter: inviter, expires_at: expiration)

        expect(invitation.expires_at).to be_within(1.second).of(expiration)
      end
    end

    describe 'defaults' do
      it 'sets status to pending if blank on create' do
        invitation = Invitation.new(
          account: account,
          inviter: inviter,
          email: 'test@example.com',
          first_name: 'Test',
          last_name: 'User'
        )
        invitation.save

        expect(invitation.status).to eq('pending')
      end

      it 'sets role_names to [member] if blank on create' do
        invitation = Invitation.new(
          account: account,
          inviter: inviter,
          email: 'test@example.com',
          first_name: 'Test',
          last_name: 'User'
        )
        invitation.save

        expect(invitation.role_names).to eq([ 'member' ])
      end
    end
  end

  describe 'state management' do
    let(:invitation) { create(:invitation, account: account, inviter: inviter) }

    describe '#accept!' do
      it 'changes status to accepted and sets accepted_at' do
        expect(invitation.accept!).to be_truthy
        expect(invitation.status).to eq('accepted')
        expect(invitation.accepted_at).to be_within(1.second).of(Time.current)
      end

      it 'returns false if invitation is expired' do
        expired = create(:invitation, :expired, account: account, inviter: inviter)
        expect(expired.accept!).to be_falsey
      end

      it 'returns false if invitation is not pending' do
        accepted = create(:invitation, :accepted, account: account, inviter: inviter)
        expect(accepted.accept!).to be_falsey
      end
    end

    describe '#cancel!' do
      it 'changes status to cancelled' do
        expect(invitation.cancel!).to be_truthy
        expect(invitation.reload.status).to eq('cancelled')
      end

      it 'returns false if invitation is expired' do
        expired = create(:invitation, :expired, account: account, inviter: inviter)
        expect(expired.cancel!).to be_falsey
      end

      it 'returns false if invitation is not pending' do
        accepted = create(:invitation, :accepted, account: account, inviter: inviter)
        expect(accepted.cancel!).to be_falsey
      end
    end

    describe '#expired?' do
      it 'returns true if expires_at is in the past' do
        expired = create(:invitation, :expired, account: account, inviter: inviter)
        expect(expired.expired?).to be true
      end

      it 'returns false if expires_at is in the future' do
        expect(invitation.expired?).to be false
      end
    end

    describe '#pending?' do
      it 'returns true for pending invitations' do
        expect(invitation.pending?).to be true
      end

      it 'returns false for accepted invitations' do
        accepted = create(:invitation, :accepted, account: account, inviter: inviter)
        expect(accepted.pending?).to be false
      end
    end

    describe '#accepted?' do
      it 'returns true for accepted invitations' do
        accepted = create(:invitation, :accepted, account: account, inviter: inviter)
        expect(accepted.accepted?).to be true
      end

      it 'returns false for pending invitations' do
        expect(invitation.accepted?).to be false
      end
    end

    describe '#cancelled?' do
      it 'returns true for cancelled invitations' do
        invitation.cancel!
        expect(invitation.cancelled?).to be true
      end

      it 'returns false for pending invitations' do
        expect(invitation.cancelled?).to be false
      end
    end
  end

  describe 'role management' do
    let(:invitation) { create(:invitation, account: account, inviter: inviter) }

    describe '#add_role' do
      it 'adds a role to role_names' do
        # Get current count
        current_count = invitation.role_names.count

        # Add new role
        invitation.add_role('billing.viewer')
        expect(invitation.role_names).to include('billing.viewer')
        expect(invitation.role_names.count).to eq(current_count + 1)
      end

      it 'does not add duplicate roles' do
        initial_count = invitation.role_names.count
        invitation.add_role('member')
        expect(invitation.role_names.count).to eq(initial_count) # No change
      end
    end

    describe '#remove_role' do
      it 'removes a role from role_names' do
        invitation.add_role('billing.viewer')
        initial_count = invitation.role_names.count

        invitation.remove_role('billing.viewer')
        expect(invitation.role_names).not_to include('billing.viewer')
        expect(invitation.role_names.count).to eq(initial_count - 1)
      end
    end

    describe '#has_role?' do
      it 'returns true if invitation has the role' do
        expect(invitation.has_role?('member')).to be true
      end

      it 'returns false if invitation does not have the role' do
        expect(invitation.has_role?('nonexistent.role')).to be false
      end

      it 'returns false if role_names is nil' do
        invitation.update_column(:role_names, nil)
        invitation.reload
        expect(invitation.has_role?('member')).to be false
      end
    end
  end

  describe 'validations' do
    let(:invitation) { build(:invitation, account: account, inviter: inviter) }

    describe '#validate_role_names' do
      it 'validates role_names is an array' do
        invitation.role_names = 'not-an-array'
        expect(invitation).not_to be_valid
        expect(invitation.errors[:role_names]).to include('must be an array')
      end

      it 'validates all role names exist' do
        invitation.role_names = [ 'member', 'invalid-role' ]
        expect(invitation).not_to be_valid
        expect(invitation.errors[:role_names]).to include(/contains invalid roles/)
      end

      it 'allows valid role names' do
        invitation.role_names = [ 'member' ]
        expect(invitation).to be_valid
      end

      it 'allows nil role_names' do
        invitation.role_names = nil
        expect(invitation).to be_valid
      end
    end

    describe '#inviter_can_send_invitations' do
      it 'validates inviter has team.invite permission' do
        # Create user without any roles/permissions
        inviter_without_permission = create(:user, account: account)
        # Remove all roles to ensure no permissions
        inviter_without_permission.roles.clear
        inviter_without_permission.reload

        invitation = build(:invitation, account: account, inviter: inviter_without_permission)

        expect(invitation).not_to be_valid
        expect(invitation.errors[:inviter]).to include('does not have permission to send invitations')
      end

      it 'allows inviter with team.invite permission' do
        # Manager user has team.invite permission
        expect(invitation).to be_valid
      end

      it 'allows inviter with users.create permission' do
        # Manager user has users.create permission
        expect(invitation).to be_valid
      end
    end
  end
end
