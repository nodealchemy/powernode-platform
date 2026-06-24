# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CodeFactoryChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contract) { create(:ai_code_factory_risk_contract, account: account) }
  let(:run) { create(:ai_code_factory_review_state, account: account) }

  before do
    stub_connection current_user: user
  end

  describe 'subscription' do
    context 'with a run belonging to the user account' do
      it 'successfully subscribes' do
        subscribe(type: 'run', id: run.id)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("code_factory:run:#{run.id}")
      end
    end

    context 'with a contract belonging to the user account' do
      it 'successfully subscribes' do
        subscribe(type: 'contract', id: contract.id)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("code_factory:contract:#{contract.id}")
      end
    end

    context 'with a run from another account (IDOR)' do
      let(:other_account) { create(:account) }
      let(:other_run) { create(:ai_code_factory_review_state, account: other_account) }

      it 'rejects the subscription' do
        subscribe(type: 'run', id: other_run.id)

        expect(subscription).to be_rejected
      end
    end

    context 'with a contract from another account (IDOR)' do
      let(:other_account) { create(:account) }
      let(:other_contract) { create(:ai_code_factory_risk_contract, account: other_account) }

      it 'rejects the subscription' do
        subscribe(type: 'contract', id: other_contract.id)

        expect(subscription).to be_rejected
      end
    end

    context 'with an unknown run id' do
      it 'rejects the subscription' do
        subscribe(type: 'run', id: SecureRandom.uuid)

        expect(subscription).to be_rejected
      end
    end

    context 'without authenticated user' do
      before { stub_connection current_user: nil }

      it 'rejects the subscription' do
        subscribe(type: 'run', id: run.id)

        expect(subscription).to be_rejected
      end
    end
  end
end
