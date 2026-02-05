# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ReviewWorkflowService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  subject(:service) { described_class.new(account: account) }

  # Helper to set up a team with review configuration
  def create_team_with_review_config(review_mode: 'blocking', auto_review: true, task_types: ['execution'])
    team = create(:ai_agent_team, account: account, review_config: {
      'auto_review_enabled' => auto_review,
      'review_mode' => review_mode,
      'review_task_types' => task_types,
      'reviewer_role_type' => 'reviewer',
      'max_revisions' => 3
    })

    reviewer_agent = create(:ai_agent, account: account, provider: provider, name: 'Reviewer Agent')

    # Create a reviewer role on the team
    reviewer_role = team.ai_team_roles.create!(
      role_name: 'reviewer',
      role_type: 'reviewer',
      description: 'Reviews task output',
      ai_agent: reviewer_agent
    )

    { team: team, reviewer_role: reviewer_role, reviewer_agent: reviewer_agent }
  end

  # Mock a completed task with team execution
  def create_completed_task(team, task_type: 'execution', output_data: { 'result' => 'success' })
    execution = double('team_execution',
      agent_team: team,
      agent_team_id: team.id
    )

    task = double('team_task',
      id: SecureRandom.uuid,
      task_type: task_type,
      status: 'completed',
      output_data: output_data,
      team_execution: execution
    )

    allow(task).to receive(:update!)

    task
  end

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end
  end

  describe '.check_completeness' do
    context 'with clean output' do
      it 'returns high completeness score' do
        result = described_class.check_completeness({ 'result' => 'All features implemented and tested' })

        expect(result['has_todos']).to be false
        expect(result['has_stubs']).to be false
        expect(result['has_empty_implementations']).to be false
        expect(result['completeness_score']).to eq(1.0)
      end
    end

    context 'with TODO markers' do
      it 'detects TODO/FIXME patterns' do
        result = described_class.check_completeness({
          'code' => "def process\n  # TODO: implement this\nend"
        })

        expect(result['has_todos']).to be true
        expect(result['completeness_score']).to be < 1.0
      end

      it 'detects FIXME patterns' do
        result = described_class.check_completeness({
          'code' => "# FIXME: broken logic here"
        })

        expect(result['has_todos']).to be true
      end

      it 'detects HACK patterns' do
        result = described_class.check_completeness({
          'code' => "# HACK: temporary workaround"
        })

        expect(result['has_todos']).to be true
      end

      it 'detects XXX patterns' do
        result = described_class.check_completeness({
          'code' => "# XXX: needs attention"
        })

        expect(result['has_todos']).to be true
      end
    end

    context 'with stub indicators' do
      it 'detects stub/placeholder patterns' do
        result = described_class.check_completeness({
          'code' => "def method\n  # placeholder implementation\nend"
        })

        expect(result['has_stubs']).to be true
        expect(result['completeness_score']).to be < 1.0
      end

      it 'detects not implemented patterns' do
        result = described_class.check_completeness({
          'code' => "def method\n  # not implemented yet\nend"
        })

        expect(result['has_stubs']).to be true
      end
    end

    context 'with empty implementations' do
      it 'detects pass keyword' do
        result = described_class.check_completeness({
          'code' => "def method\n  pass\nend"
        })

        expect(result['has_empty_implementations']).to be true
        expect(result['completeness_score']).to be < 1.0
      end

      it 'detects ellipsis (...)' do
        result = described_class.check_completeness({
          'code' => "def method\n  ...\nend"
        })

        expect(result['has_empty_implementations']).to be true
      end

      it 'detects raise NotImplementedError' do
        result = described_class.check_completeness({
          'code' => "def method\n  raise NotImplementedError\nend"
        })

        expect(result['has_empty_implementations']).to be true
      end
    end

    context 'with multiple issues' do
      it 'reduces completeness score for each issue' do
        result = described_class.check_completeness({
          'code' => "# TODO: implement\n# stub\n  pass\n"
        })

        expect(result['has_todos']).to be true
        expect(result['has_stubs']).to be true
        expect(result['has_empty_implementations']).to be true
        expect(result['completeness_score']).to eq(0.25)
      end
    end

    context 'with empty output' do
      it 'returns clean result for empty hash' do
        result = described_class.check_completeness({})

        expect(result['has_todos']).to be false
        expect(result['completeness_score']).to eq(1.0)
      end
    end
  end

  describe '#process_review' do
    let(:setup) { create_team_with_review_config }
    let(:team) { setup[:team] }
    let(:reviewer_role) { setup[:reviewer_role] }

    let(:review) do
      create(:ai_task_review,
        account: account,
        reviewer_role: reviewer_role,
        reviewer_agent: setup[:reviewer_agent],
        status: 'in_progress',
        review_mode: 'blocking'
      )
    end

    context 'with approve result' do
      it 'approves the review' do
        allow(review).to receive(:approve!)
        allow(review).to receive(:review_mode).and_return('blocking')
        allow(review).to receive(:team_task).and_return(
          double('task', status: 'waiting', update!: true)
        )

        result = service.process_review(review, result: 'approve', notes: 'Looks good')
        expect(result).to eq(review)
      end
    end

    context 'with reject result' do
      it 'rejects the review' do
        allow(review).to receive(:reject!)
        allow(review).to receive(:rejection_reason).and_return('Quality issues')
        allow(review).to receive(:review_mode).and_return('blocking')
        allow(review).to receive(:team_task).and_return(
          double('task', status: 'waiting', update!: true)
        )

        result = service.process_review(review, result: 'reject', notes: 'Quality issues')
        expect(result).to eq(review)
      end
    end

    context 'with revision result' do
      it 'requests revision' do
        allow(review).to receive(:request_revision!)
        allow(review).to receive(:revision_count).and_return(1)
        allow(review).to receive(:review_mode).and_return('blocking')
        allow(review).to receive(:rejection_reason).and_return('Needs improvement')
        allow(review).to receive(:team_task).and_return(
          double('task', status: 'waiting', output_data: {}, update!: true,
                 team_execution: double('exec', agent_team: team))
        )

        result = service.process_review(review, result: 'revision', notes: 'Needs improvement')
        expect(result).to eq(review)
      end
    end

    context 'with invalid result' do
      it 'raises ArgumentError' do
        expect {
          service.process_review(review, result: 'invalid_action')
        }.to raise_error(ArgumentError, /Invalid review action/)
      end
    end
  end

  describe '#list_reviews' do
    it 'returns reviews for a given task' do
      task_id = SecureRandom.uuid
      result = service.list_reviews(task_id)
      expect(result).to respond_to(:each)
    end
  end
end
