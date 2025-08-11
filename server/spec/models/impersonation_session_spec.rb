# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImpersonationSession, type: :model do
  include ActiveSupport::Testing::TimeHelpers
  
  subject { build(:impersonation_session) }

  # Associations
  describe 'associations' do
    it { should belong_to(:impersonator).class_name('User') }
    it { should belong_to(:impersonated_user).class_name('User') }
    it { should belong_to(:account) }
  end

  # Validations
  describe 'validations' do
    it { should validate_presence_of(:session_token) }
    it { should validate_uniqueness_of(:session_token) }
    it { should validate_length_of(:reason).is_at_most(500) }
    it { should validate_length_of(:ip_address).is_at_most(45) }
    it { should validate_length_of(:user_agent).is_at_most(500) }
    it { should validate_presence_of(:started_at) }

    it 'validates same account for impersonator and impersonated user' do
      account1 = create(:account)
      account2 = create(:account)
      impersonator = create(:user, account: account1)
      target_user = create(:user, account: account2)

      session = build(:impersonation_session, 
                     impersonator: impersonator, 
                     impersonated_user: target_user)

      expect(session).not_to be_valid
      expect(session.errors[:base]).to include('Impersonator and impersonated user must be in the same account')
    end

    it 'prevents self-impersonation' do
      user = create(:user)
      session = build(:impersonation_session, 
                     impersonator: user, 
                     impersonated_user: user)

      expect(session).not_to be_valid
      expect(session.errors[:base]).to include('Cannot impersonate yourself')
    end
  end

  # Scopes
  describe 'scopes' do
    let!(:active_session) { create(:impersonation_session, active: true) }
    let!(:ended_session) { create(:impersonation_session, active: false) }

    it '.active returns only active sessions' do
      expect(ImpersonationSession.active).to include(active_session)
      expect(ImpersonationSession.active).not_to include(ended_session)
    end

    it '.ended returns only ended sessions' do
      expect(ImpersonationSession.ended).to include(ended_session)
      expect(ImpersonationSession.ended).not_to include(active_session)
    end

    it '.recent orders by started_at desc' do
      old_session = create(:impersonation_session, started_at: 2.days.ago)
      new_session = create(:impersonation_session, started_at: 1.hour.ago)

      expect(ImpersonationSession.recent).to eq([new_session, active_session, ended_session, old_session])
    end
  end

  # Instance methods
  describe '#active?' do
    it 'returns true when active and not expired' do
      session = create(:impersonation_session, active: true, started_at: 1.hour.ago)
      expect(session.active?).to be true
    end

    it 'returns false when not active' do
      session = create(:impersonation_session, active: false)
      expect(session.active?).to be false
    end

    it 'returns false when expired' do
      session = create(:impersonation_session, 
                      active: true, 
                      started_at: ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour)
      expect(session.active?).to be false
    end
  end

  describe '#expired?' do
    it 'returns false for recent session' do
      session = create(:impersonation_session, started_at: 1.hour.ago)
      expect(session.expired?).to be false
    end

    it 'returns true for old session' do
      session = create(:impersonation_session, 
                      started_at: ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour)
      expect(session.expired?).to be true
    end

    it 'returns false when started_at is nil' do
      session = build(:impersonation_session, started_at: nil)
      expect(session.expired?).to be false
    end
  end

  describe '#duration' do
    it 'returns duration when session is ended' do
      session = create(:impersonation_session,
                      started_at: 2.hours.ago,
                      ended_at: 1.hour.ago)
      expect(session.duration).to eq(1.hour)
    end

    it 'returns duration from start to current time when session is active' do
      travel_to Time.current do
        session = create(:impersonation_session, started_at: 1.hour.ago, ended_at: nil)
        expect(session.duration).to be_within(1.second).of(1.hour)
      end
    end

    it 'returns nil when started_at is nil' do
      session = build(:impersonation_session, started_at: nil)
      expect(session.duration).to be_nil
    end
  end

  describe '#end_session!' do
    it 'sets active to false and ended_at to current time' do
      travel_to Time.current do
        session = create(:impersonation_session, active: true, ended_at: nil)
        session.end_session!

        expect(session.active).to be false
        expect(session.ended_at).to eq(Time.current)
      end
    end
  end

  # Class methods
  describe '.cleanup_expired_sessions' do
    it 'marks expired active sessions as ended' do
      expired_session = create(:impersonation_session,
                              active: true,
                              started_at: ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour)
      active_session = create(:impersonation_session,
                             active: true,
                             started_at: 1.hour.ago)

      travel_to Time.current do
        count = ImpersonationSession.cleanup_expired_sessions

        expect(count).to eq(1)
        expect(expired_session.reload.active).to be false
        expect(expired_session.ended_at).to eq(Time.current)
        expect(active_session.reload.active).to be true
      end
    end

    it 'returns count of cleaned up sessions' do
      create_list(:impersonation_session, 3,
                 active: true,
                 started_at: ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour)

      count = ImpersonationSession.cleanup_expired_sessions
      expect(count).to eq(3)
    end
  end

  describe '.active_session_for_user' do
    it 'returns active session for user' do
      user = create(:user)
      session = create(:impersonation_session, impersonated_user: user, active: true)
      ended_session = create(:impersonation_session, impersonated_user: user, active: false)

      expect(ImpersonationSession.active_session_for_user(user.id)).to eq(session)
    end

    it 'returns nil when no active session exists' do
      user = create(:user)
      create(:impersonation_session, impersonated_user: user, active: false)

      expect(ImpersonationSession.active_session_for_user(user.id)).to be_nil
    end
  end

  describe '.create_session!' do
    let(:account) { create(:account) }
    let(:impersonator) { create(:user, account: account) }
    let(:target_user) { create(:user, account: account) }

    it 'creates a new impersonation session' do
      expect {
        ImpersonationSession.create_session!(
          impersonator: impersonator,
          impersonated_user: target_user,
          reason: 'Testing purposes',
          ip_address: '127.0.0.1',
          user_agent: 'Test Agent'
        )
      }.to change(ImpersonationSession, :count).by(1)

      session = ImpersonationSession.last
      expect(session.impersonator).to eq(impersonator)
      expect(session.impersonated_user).to eq(target_user)
      expect(session.account).to eq(target_user.account)
      expect(session.reason).to eq('Testing purposes')
      expect(session.ip_address).to eq('127.0.0.1')
      expect(session.user_agent).to eq('Test Agent')
      expect(session.active).to be true
    end

    it 'ends existing active sessions for the target user' do
      existing_session = create(:impersonation_session, 
                               impersonated_user: target_user, 
                               active: true)

      travel_to Time.current do
        ImpersonationSession.create_session!(
          impersonator: impersonator,
          impersonated_user: target_user
        )

        expect(existing_session.reload.active).to be false
        expect(existing_session.ended_at).to eq(Time.current)
      end
    end
  end

  # Callbacks
  describe 'callbacks' do
    it 'sets started_at on creation' do
      travel_to Time.current do
        session = build(:impersonation_session, started_at: nil)
        session.save!
        expect(session.started_at).to eq(Time.current)
      end
    end

    it 'generates session_token on creation' do
      session = build(:impersonation_session, session_token: nil)
      session.save!
      expect(session.session_token).to be_present
      expect(session.session_token.length).to eq(64) # 32 bytes hex = 64 characters
    end

    it 'sets account from impersonated user on creation' do
      account = create(:account)
      target_user = create(:user, account: account)
      session = build(:impersonation_session, impersonated_user: target_user, account: nil)
      session.save!
      expect(session.account).to eq(account)
    end
  end
end