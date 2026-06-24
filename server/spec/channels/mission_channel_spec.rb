# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MissionChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account) }

  before do
    stub_connection current_user: user
  end

  describe 'subscription' do
    context 'with a mission belonging to the user account' do
      it 'successfully subscribes' do
        subscribe(type: 'mission', id: mission.id)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("mission:mission:#{mission.id}")
      end
    end

    context 'with a mission from another account (IDOR)' do
      let(:other_account) { create(:account) }
      let(:other_mission) { create(:ai_mission, account: other_account) }

      it 'rejects the subscription' do
        subscribe(type: 'mission', id: other_mission.id)

        expect(subscription).to be_rejected
      end
    end

    context 'with an unknown mission id' do
      it 'rejects the subscription' do
        subscribe(type: 'mission', id: SecureRandom.uuid)

        expect(subscription).to be_rejected
      end
    end

    context 'with the account stream for the user account' do
      it 'successfully subscribes' do
        subscribe(type: 'account', id: account.id)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("mission:account:#{account.id}")
      end
    end

    context 'without authenticated user' do
      before { stub_connection current_user: nil }

      it 'rejects the subscription' do
        subscribe(type: 'mission', id: mission.id)

        expect(subscription).to be_rejected
      end
    end
  end
end
