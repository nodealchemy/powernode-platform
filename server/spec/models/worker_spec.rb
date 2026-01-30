# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Worker, type: :model do
  describe 'associations' do
    it { should belong_to(:account).optional }
    it { should have_many(:worker_activities).dependent(:destroy) }
    it { should have_many(:worker_roles).dependent(:destroy) }
    it { should have_many(:roles).through(:worker_roles) }
  end

  describe 'validations' do
    subject { build(:worker) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_least(3).is_at_most(50) }
    it { should validate_length_of(:description).is_at_most(255) }
    it { should validate_presence_of(:status) }

    describe 'only_one_system_worker_globally' do
      context 'when creating a system worker' do
        let!(:existing_system_worker) { create(:worker, :system_worker) }

        it 'prevents creating a second system worker' do
          new_system_worker = build(:worker, account: nil)
          new_system_worker.valid?
          expect(new_system_worker.errors[:base]).to include('Only one system worker is allowed globally')
        end
      end

      context 'when creating an account worker' do
        let!(:existing_system_worker) { create(:worker, :system_worker) }
        let(:account) { create(:account) }

        it 'allows creating account workers' do
          account_worker = build(:worker, account: account)
          expect(account_worker).to be_valid
        end
      end
    end
  end

  describe 'AASM states and transitions' do
    let(:worker) { create(:worker, status: 'active') }

    describe 'initial state' do
      it 'is active by default' do
        new_worker = Worker.new
        expect(new_worker.status).to eq('active')
      end
    end

    describe '#suspend!' do
      it 'transitions from active to suspended' do
        expect { worker.suspend! }.to change { worker.status }.from('active').to('suspended')
      end
    end

    describe '#activate!' do
      let(:suspended_worker) { create(:worker, :suspended) }

      it 'transitions from suspended to active' do
        expect { suspended_worker.activate! }.to change { suspended_worker.status }.from('suspended').to('active')
      end
    end

    describe '#revoke!' do
      it 'transitions from active to revoked' do
        expect { worker.revoke! }.to change { worker.status }.from('active').to('revoked')
      end

      it 'transitions from suspended to revoked' do
        suspended_worker = create(:worker, :suspended)
        expect { suspended_worker.revoke! }.to change { suspended_worker.status }.from('suspended').to('revoked')
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:active_worker) { create(:worker, status: 'active', account: account) }
    let!(:suspended_worker) { create(:worker, :suspended, account: account) }
    let!(:system_worker) { create(:worker, :system_worker) }

    describe '.active' do
      it 'returns only active workers' do
        expect(Worker.active).to include(active_worker)
        expect(Worker.active).not_to include(suspended_worker)
      end
    end

    describe '.for_account' do
      it 'returns workers for specific account' do
        expect(Worker.for_account(account)).to include(active_worker, suspended_worker)
        expect(Worker.for_account(account)).not_to include(system_worker)
      end
    end

    describe '.system_workers' do
      it 'returns only system workers' do
        expect(Worker.system_workers).to include(system_worker)
        expect(Worker.system_workers).not_to include(active_worker)
      end
    end

    describe '.account_workers' do
      it 'returns only account workers' do
        expect(Worker.account_workers).to include(active_worker, suspended_worker)
        expect(Worker.account_workers).not_to include(system_worker)
      end
    end
  end

  describe 'instance methods' do
    describe '#system?' do
      it 'returns true for system workers' do
        system_worker = create(:worker, :system_worker)
        expect(system_worker.system?).to be true
      end

      it 'returns false for account workers' do
        account_worker = create(:worker)
        expect(account_worker.system?).to be false
      end
    end

    describe '#account?' do
      it 'returns true for account workers' do
        account_worker = create(:worker)
        expect(account_worker.account?).to be true
      end

      it 'returns false for system workers' do
        system_worker = create(:worker, :system_worker)
        expect(system_worker.account?).to be false
      end
    end

    describe '#regenerate_token!' do
      let(:worker) { create(:worker) }

      it 'changes the token_digest' do
        old_digest = worker.token_digest
        worker.regenerate_token!
        expect(worker.reload.token_digest).not_to eq(old_digest)
      end

      it 'returns the new token' do
        new_token = worker.regenerate_token!
        expect(new_token).to be_present
        expect(new_token).to start_with('swt_')
      end

      it 'sets the virtual token attribute' do
        new_token = worker.regenerate_token!
        expect(worker.token).to eq(new_token)
      end
    end

    describe '#masked_token' do
      let(:worker) { create(:worker) }

      it 'returns a masked verification hash when token_digest is present' do
        expect(worker.masked_token).to be_present
        expect(worker.masked_token).to include('******')
      end

      it 'returns empty string when token_digest is blank' do
        worker.token_digest = nil
        expect(worker.masked_token).to eq('')
      end
    end

    describe '#display_name' do
      let(:worker) { create(:worker) }

      it 'returns name with account name' do
        expect(worker.display_name).to eq("#{worker.name} (#{worker.account.name})")
      end
    end

    describe '#auth_token' do
      let(:worker) { create(:worker) }

      it 'returns the virtual token attribute' do
        worker.token = 'test_token'
        expect(worker.auth_token).to eq('test_token')
      end
    end

    describe '#active_in_last_hours' do
      let(:worker) { create(:worker) }

      it 'returns true when last_seen_at is within the specified hours' do
        worker.update_columns(last_seen_at: 1.hour.ago)
        expect(worker.active_in_last_hours(24)).to be true
      end

      it 'returns false when last_seen_at is older than specified hours' do
        worker.update_columns(last_seen_at: 48.hours.ago)
        expect(worker.active_in_last_hours(24)).to be false
      end
    end
  end
end
