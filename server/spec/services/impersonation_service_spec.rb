# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImpersonationService, type: :service do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  # Create owner first in account, then admin and member users
  let!(:owner) { create(:user, :owner, account: account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:target_user) { create(:user, :member, account: account) }
  let(:service) { described_class.new(admin_user) }

  # Ensure admin has impersonation permission through their role
  before do
    # The admin role should already have impersonation permission from seeds
    # If not, we'll add it explicitly
    unless admin_user.has_permission?('admin.users.impersonate')
      admin_user.add_role('admin')
    end
  end

  describe '#start_impersonation' do
    let(:valid_params) do
      {
        target_user_id: target_user.id,
        reason: 'Testing purposes',
        ip_address: '127.0.0.1',
        user_agent: 'Test Agent'
      }
    end

    context 'with valid parameters' do
      it 'creates an impersonation session' do
        expect {
          service.start_impersonation(**valid_params)
        }.to change(ImpersonationSession, :count).by(1)
      end

      it 'returns an impersonation token' do
        token = service.start_impersonation(**valid_params)
        expect(token).to be_present

        # Verify UserToken was created with correct metadata
        # Token is database-backed (not JWT), so verify via UserToken lookup
        user_token = UserToken.find_by_token(token)
        expect(user_token).to be_present
        expect(user_token.token_type).to eq('impersonation')
        expect(user_token.user_id).to eq(target_user.id)
        expect(user_token.metadata['impersonator_id']).to eq(admin_user.id)
      end

      it 'creates an audit log entry' do
        expect {
          service.start_impersonation(**valid_params)
        }.to change(AuditLog, :count).by_at_least(1)

        # Find the specific impersonation_started audit log
        log = AuditLog.find_by(action: 'impersonation_started')
        expect(log).to be_present
        expect(log.user).to eq(admin_user)
        expect(log.resource_type).to eq('User')
        expect(log.resource_id).to eq(target_user.id)
        expect(log.metadata['impersonated_user_email']).to eq(target_user.email)
        expect(log.metadata['reason']).to eq('Testing purposes')
      end
    end

    context 'permission validation' do
      it 'raises PermissionDeniedError when user lacks impersonation permission' do
        user_without_permission = create(:user, :member, account: account)
        service = described_class.new(user_without_permission)

        expect {
          service.start_impersonation(**valid_params)
        }.to raise_error(ImpersonationService::PermissionDeniedError, 
                        'You do not have permission to impersonate other users')
      end

      it 'allows owner to impersonate without explicit permission' do
        owner_user = create(:user, :owner, account: account)
        service = described_class.new(owner_user)

        expect {
          service.start_impersonation(**valid_params)
        }.not_to raise_error
      end

      it 'allows admin to impersonate without explicit permission' do
        admin_without_permission = create(:user, :admin, account: account)
        service = described_class.new(admin_without_permission)

        expect {
          service.start_impersonation(**valid_params)
        }.not_to raise_error
      end
    end

    context 'security validations' do
      it 'raises InvalidUserError for users in different accounts' do
        other_account = create(:account)
        other_user = create(:user, account: other_account)

        expect {
          service.start_impersonation(target_user_id: other_user.id)
        }.to raise_error(ImpersonationService::InvalidUserError, 
                        'You can only impersonate users in your own account')
      end

      it 'raises SelfImpersonationError when trying to impersonate self' do
        expect {
          service.start_impersonation(target_user_id: admin_user.id)
        }.to raise_error(ImpersonationService::SelfImpersonationError, 
                        'You cannot impersonate yourself')
      end

      it 'raises InvalidUserError for inactive users' do
        target_user.update!(status: 'inactive')

        expect {
          service.start_impersonation(**valid_params)
        }.to raise_error(ImpersonationService::InvalidUserError, 
                        'Cannot impersonate inactive user')
      end

      it 'prevents non-owners from impersonating owners' do
        owner_user = create(:user, :owner, account: account)

        expect {
          service.start_impersonation(target_user_id: owner_user.id)
        }.to raise_error(ImpersonationService::PermissionDeniedError, 
                        'Only owners can impersonate other owners')
      end

      it 'allows owners to impersonate other owners' do
        owner_user = create(:user, :owner, account: account)
        target_owner = create(:user, :owner, account: account)
        service = described_class.new(owner_user)

        expect {
          service.start_impersonation(target_user_id: target_owner.id)
        }.not_to raise_error
      end
    end
  end

  describe '#end_impersonation' do
    let!(:session) do
      create(:impersonation_session,
             impersonator: admin_user,
             impersonated_user: target_user,
)
    end

    context 'with valid session token' do
      it 'ends the impersonation session' do
        service.end_impersonation(session.session_token)
        expect(session.reload.active?).to be false
        expect(session.ended_at).to be_present
      end

      it 'creates an audit log entry' do
        expect {
          service.end_impersonation(session.session_token)
        }.to change(AuditLog, :count).by_at_least(1)

        # Find the specific impersonation_ended audit log
        log = AuditLog.find_by(action: 'impersonation_ended')
        expect(log).to be_present
        expect(log.user).to eq(admin_user)
        expect(log.resource_type).to eq('User')
        expect(log.resource_id).to eq(target_user.id)
        expect(log.metadata['impersonated_user_email']).to eq(target_user.email)
        expect(log.metadata['session_id']).to eq(session.id)
      end

      it 'returns the ended session' do
        result = service.end_impersonation(session.session_token)
        expect(result).to eq(session)
        expect(result.active?).to be false
      end
    end

    context 'with invalid session token' do
      it 'raises SessionNotFoundError for non-existent session' do
        expect {
          service.end_impersonation('invalid_token')
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'raises PermissionDeniedError for other user\'s session' do
        other_user = create(:user, :admin, account: account)
        other_service = described_class.new(other_user)

        expect {
          other_service.end_impersonation(session.session_token)
        }.to raise_error(ImpersonationService::PermissionDeniedError, 
                        'You can only end your own impersonation sessions')
      end
    end
  end

  describe '#list_active_sessions' do
    let!(:active_session1) do
      create(:impersonation_session,
             impersonator: admin_user,
             impersonated_user: target_user)
    end
    let!(:active_session2) do
      create(:impersonation_session,
             impersonator: admin_user,
             impersonated_user: create(:user, :member, account: account))
    end
    let!(:ended_session) do
      create(:impersonation_session, :ended)
    end
    let!(:other_account_session) do
      other_account = create(:account)
      other_impersonator = create(:user, :admin, account: other_account)
      other_target = create(:user, :member, account: other_account)
      create(:impersonation_session,
             impersonator: other_impersonator,
             impersonated_user: other_target
      )
    end

    it 'returns only active sessions for the account' do
      sessions = service.list_active_sessions
      expect(sessions).to include(active_session1, active_session2)
      expect(sessions).not_to include(ended_session, other_account_session)
    end

    it 'includes associated users' do
      sessions = service.list_active_sessions
      expect(sessions.first.impersonator).to be_present
      expect(sessions.first.impersonated_user).to be_present
    end

    it 'orders by most recent first' do
      old_session = nil
      travel_to 1.hour.ago do
        old_session = create(:impersonation_session,
                           impersonator: admin_user,
                           impersonated_user: create(:user, :member, account: account))
      end

      sessions = service.list_active_sessions
      expect(sessions.count).to be >= 2  # Should include our new session plus others
      expect(sessions.first.started_at).to be > sessions.last.started_at
    end
  end

  describe '#get_session_history' do
    it 'returns sessions for the account with limit' do
      create_list(:impersonation_session, 3,
                  impersonator: admin_user,
                  impersonated_user: target_user)
      
      sessions = service.get_session_history(limit: 2)
      expect(sessions.count).to eq(2)
    end

    it 'defaults to 50 sessions limit' do
      allow(ImpersonationSession).to receive(:for_account).and_return(
        double(includes: double(recent: double(limit: double)))
      )

      service.get_session_history
      expect(ImpersonationSession).to have_received(:for_account).with(admin_user.account_id)
    end
  end

  describe '#validate_impersonation_token' do
    let!(:session) do
      create(:impersonation_session,
             impersonator: admin_user,
             impersonated_user: target_user)
    end

    let(:valid_token) do
      payload = {
        user_id: target_user.id,
        impersonator_id: admin_user.id,
        session_id: session.id,
        type: 'impersonation',
        exp: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).to_i
      }
      JwtService.encode(payload)
    end

    it 'returns session for valid active token' do
      result = service.validate_impersonation_token(valid_token)
      expect(result).to eq(session)
    end

    it 'returns nil for invalid token format' do
      result = service.validate_impersonation_token('invalid_token')
      expect(result).to be_nil
    end

    it 'returns nil for non-impersonation token' do
      regular_token = JwtService.encode({ user_id: target_user.id })
      result = service.validate_impersonation_token(regular_token)
      expect(result).to be_nil
    end

    it 'returns nil for expired session' do
      # Create a session that started too long ago (expired) but with a valid JWT token
      expired_session = create(:impersonation_session, 
                               impersonator: admin_user,
                               impersonated_user: target_user,
                                                              started_at: ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour,
                  )
      
      expired_token = JwtService.encode({
        user_id: target_user.id,
        impersonator_id: admin_user.id,
        session_id: expired_session.id,
        type: 'impersonation',
        exp: 1.hour.from_now.to_i  # JWT token is still valid
      })
      
      result = service.validate_impersonation_token(expired_token)
      expect(result).to be_nil
      expect(expired_session.reload.active?).to be false
    end

    it 'returns nil for non-existent session' do
      payload = {
        user_id: target_user.id,
        impersonator_id: admin_user.id,
        session_id: 'non-existent-id',
        type: 'impersonation',
        exp: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).to_i
      }
      invalid_token = JwtService.encode(payload)

      result = service.validate_impersonation_token(invalid_token)
      expect(result).to be_nil
    end

    it 'returns nil for inactive session' do
      session.update!(ended_at: Time.current)
      result = service.validate_impersonation_token(valid_token)
      expect(result).to be_nil
    end
  end

  describe '.cleanup_expired_sessions' do
    it 'delegates to ImpersonationSession.cleanup_expired_sessions' do
      allow(ImpersonationSession).to receive(:cleanup_expired_sessions)
      
      described_class.cleanup_expired_sessions
      
      expect(ImpersonationSession).to have_received(:cleanup_expired_sessions)
    end
  end
end