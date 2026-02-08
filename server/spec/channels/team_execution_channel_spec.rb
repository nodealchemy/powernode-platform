# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamExecutionChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:team) { create(:ai_agent_team, account: account) }

  before do
    stub_connection current_user: user
  end

  describe 'subscription' do
    context 'with valid team belonging to user account' do
      it 'successfully subscribes' do
        subscribe(team_id: team.id)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("team_execution:#{team.id}")
      end

      it 'sends confirmation message' do
        subscribe(team_id: team.id)

        expect(transmissions.last).to include(
          'type' => 'subscription.confirmed',
          'channel' => 'team_execution',
          'team_id' => team.id
        )
      end
    end

    context 'without team_id' do
      it 'rejects the subscription' do
        subscribe(team_id: nil)

        expect(subscription).to be_rejected
      end
    end

    context 'with team from another account' do
      let(:other_account) { create(:account) }
      let(:other_team) { create(:ai_agent_team, account: other_account) }

      it 'rejects the subscription' do
        subscribe(team_id: other_team.id)

        expect(subscription).to be_rejected
      end
    end

    context 'without authenticated user' do
      before do
        stub_connection current_user: nil
      end

      it 'rejects the subscription' do
        subscribe(team_id: team.id)

        expect(subscription).to be_rejected
      end
    end
  end

  describe '.broadcast_to_team' do
    it 'broadcasts event to the correct stream' do
      expect {
        TeamExecutionChannel.broadcast_to_team(
          team.id,
          'execution_started',
          execution_id: 'exec_abc123',
          job_id: 'job_xyz'
        )
      }.to have_broadcasted_to("team_execution:#{team.id}").with(
        hash_including(
          type: 'execution_started',
          team_id: team.id,
          execution_id: 'exec_abc123',
          job_id: 'job_xyz'
        )
      )
    end

    it 'includes timestamp in broadcasts' do
      expect {
        TeamExecutionChannel.broadcast_to_team(team.id, 'member_completed', member_name: 'Agent1')
      }.to have_broadcasted_to("team_execution:#{team.id}").with(
        hash_including(timestamp: be_a(String))
      )
    end
  end
end
