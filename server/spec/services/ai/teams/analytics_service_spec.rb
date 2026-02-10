# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Teams::AnalyticsService, type: :service do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, account: account) }
  let(:agent1) { create(:ai_agent, account: account) }
  let(:agent2) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe '#get_team_analytics' do
    it 'returns all 8 top-level keys with correct period' do
      result = service.get_team_analytics(team.id)
      expect(result.keys).to contain_exactly(
        :period_days, :generated_at, :overview, :performance, :cost, :agents, :communication, :quality
      )
      expect(result[:period_days]).to eq(30)
      expect(result[:generated_at]).to be_a(String)
    end

    describe 'overview section' do
      let!(:role) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'w', role_type: 'worker') }
      let!(:exec_c1) do
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed',
          objective: 'A', total_tokens_used: 1000, total_cost_usd: 0.50,
          started_at: 2.hours.ago, completed_at: 1.hour.ago, duration_ms: 3_600_000)
      end
      let!(:exec_c2) do
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed',
          objective: 'B', total_tokens_used: 2000, total_cost_usd: 1.00,
          started_at: 3.hours.ago, completed_at: 2.hours.ago, duration_ms: 3_600_000)
      end
      let!(:exec_f) do
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'failed',
          objective: 'C', total_tokens_used: 500, total_cost_usd: 0.25,
          started_at: 4.hours.ago, completed_at: 3.hours.ago, duration_ms: 1_800_000, termination_reason: 'error')
      end
      let!(:task1) { Ai::TeamTask.create!(team_execution: exec_c1, description: 'T1', status: 'completed', task_type: 'execution', assigned_role: role) }
      let!(:task2) { Ai::TeamTask.create!(team_execution: exec_c1, description: 'T2', status: 'failed', task_type: 'execution') }

      it 'returns correct counts, rates, tokens, cost, and day groupings' do
        overview = service.get_team_analytics(team.id)[:overview]

        expect(overview[:total_executions]).to eq(3)
        expect(overview[:completed_executions]).to eq(2)
        expect(overview[:failed_executions]).to eq(1)
        expect(overview[:cancelled_executions]).to eq(0)
        expect(overview[:active_executions]).to eq(0)
        expect(overview[:success_rate]).to eq(66.67)
        expect(overview[:total_tokens_used]).to eq(3500)
        expect(overview[:total_cost_usd]).to eq(1.75)
        expect(overview[:total_tasks]).to eq(2)
        expect(overview[:completed_tasks]).to eq(1)
        expect(overview[:failed_tasks]).to eq(1)
        expect(overview[:executions_by_day]).to be_a(Hash)
        expect(overview[:cost_by_day]).to be_a(Hash)
      end
    end

    describe 'performance section' do
      let!(:e1) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'Fast', duration_ms: 1000, started_at: 2.hours.ago, completed_at: 1.hour.ago) }
      let!(:e2) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'Med', duration_ms: 5000, started_at: 3.hours.ago, completed_at: 2.hours.ago) }
      let!(:e3) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'Slow one here', duration_ms: 10000, started_at: 4.hours.ago, completed_at: 3.hours.ago) }
      let!(:ef) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'failed', objective: 'Broken', duration_ms: 500, termination_reason: 'timeout', started_at: 5.hours.ago, completed_at: 4.hours.ago) }

      it 'calculates duration stats, status breakdown, slowest list, and termination reasons' do
        perf = service.get_team_analytics(team.id)[:performance]

        expect(perf[:min_duration_ms]).to eq(1000)
        expect(perf[:max_duration_ms]).to eq(10000)
        expect(perf[:avg_duration_ms]).to be_a(Numeric)
        expect(perf[:median_duration_ms]).to eq(5000)
        expect(perf[:p95_duration_ms]).to eq(10000)
        expect(perf[:status_breakdown]).to include('completed' => 3, 'failed' => 1)
        expect(perf[:slowest_executions].length).to be <= 5
        expect(perf[:slowest_executions].first[:duration_ms]).to eq(10000)
        expect(perf[:termination_reasons]).to include('timeout' => 1)
      end
    end

    describe 'cost section' do
      let!(:e1) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'Cheap', total_tokens_used: 100, total_cost_usd: 0.10, started_at: 2.hours.ago, completed_at: 1.hour.ago) }
      let!(:e2) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'Expensive', total_tokens_used: 5000, total_cost_usd: 2.50, started_at: 3.hours.ago, completed_at: 2.hours.ago) }
      let!(:t1) { Ai::TeamTask.create!(team_execution: e1, description: 'Task', status: 'completed', task_type: 'execution') }

      it 'calculates total, average, per-task cost and top executions' do
        cost = service.get_team_analytics(team.id)[:cost]

        expect(cost[:total_cost_usd]).to eq(2.60)
        expect(cost[:total_tokens]).to eq(5100)
        expect(cost[:avg_cost_per_execution]).to eq(1.30)
        expect(cost[:cost_per_task]).to eq(2.60)
        expect(cost[:cost_by_day]).to be_a(Hash)
        expect(cost[:top_cost_executions]).to be_an(Array)
        expect(cost[:top_cost_executions].first[:cost_usd]).to eq(2.50)
      end
    end

    describe 'agents section' do
      let!(:r1) { Ai::TeamRole.create!(account: account, agent_team: team, ai_agent: agent1, role_name: 'developer', role_type: 'worker') }
      let!(:r2) { Ai::TeamRole.create!(account: account, agent_team: team, ai_agent: agent2, role_name: 'reviewer', role_type: 'reviewer') }
      let!(:exec) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'Build', started_at: 2.hours.ago, completed_at: 1.hour.ago) }
      let!(:td) { Ai::TeamTask.create!(team_execution: exec, description: 'Code', status: 'completed', task_type: 'execution', assigned_role: r1, tokens_used: 500, cost_usd: 0.25, tools_used: %w[file_read file_write], duration_ms: 3000) }
      let!(:tr) { Ai::TeamTask.create!(team_execution: exec, description: 'Review', status: 'completed', task_type: 'review', assigned_role: r2, tokens_used: 200, cost_usd: 0.10, duration_ms: 1000) }
      let!(:tu) { Ai::TeamTask.create!(team_execution: exec, description: 'Pending', status: 'pending', task_type: 'execution') }

      it 'returns role stats, workload, task type distribution, and unassigned count' do
        agents = service.get_team_analytics(team.id)[:agents]

        expect(agents[:role_stats].length).to eq(2)
        dev = agents[:role_stats].find { |r| r[:role_name] == 'developer' }
        expect(dev[:tasks_total]).to eq(1)
        expect(dev[:tasks_completed]).to eq(1)
        expect(dev[:total_tokens]).to eq(500)
        expect(dev[:tools_used]).to include('file_read' => 1, 'file_write' => 1)
        expect(agents[:workload_by_role]).to include('developer' => 1, 'reviewer' => 1)
        expect(agents[:task_type_distribution]).to include('execution' => 2, 'review' => 1)
        expect(agents[:unassigned_tasks]).to eq(1)
      end
    end

    describe 'communication section' do
      let!(:r1) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'lead', role_type: 'manager') }
      let!(:r2) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }
      let!(:exec) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'Comms', started_at: 1.hour.ago) }
      let!(:m1) { Ai::TeamMessage.create!(team_execution: exec, from_role: r1, to_role: r2, message_type: 'task_update', content: 'Update', priority: 'normal') }
      let!(:m2) { Ai::TeamMessage.create!(team_execution: exec, from_role: r2, to_role: r1, message_type: 'escalation', content: 'Help', priority: 'high') }
      let!(:m3) { Ai::TeamMessage.create!(team_execution: exec, from_role: r2, to_role: r1, message_type: 'question', content: 'How?', requires_response: true, responded_at: 5.minutes.ago) }
      let!(:m4) { Ai::TeamMessage.create!(team_execution: exec, message_type: 'broadcast', content: 'Announce', priority: 'normal') }

      it 'returns type distribution, escalation metrics, response tracking, and interactions' do
        comm = service.get_team_analytics(team.id)[:communication]

        expect(comm[:total_messages]).to eq(4)
        expect(comm[:message_type_distribution]).to include('task_update' => 1, 'escalation' => 1, 'question' => 1, 'broadcast' => 1)
        expect(comm[:escalation_count]).to eq(1)
        expect(comm[:escalation_rate]).to eq(25.0)
        expect(comm[:response_rate]).to eq(100.0)
        expect(comm[:pending_responses]).to eq(0)
        expect(comm[:high_priority_count]).to eq(1)
        expect(comm[:broadcasts_count]).to eq(1)
        interaction = comm[:role_interactions].find { |i| i[:from] == 'lead' && i[:to] == 'dev' }
        expect(interaction[:count]).to eq(1)
      end
    end

    describe 'quality section - reviews' do
      let!(:exec) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'QA', started_at: 2.hours.ago, completed_at: 1.hour.ago) }
      let!(:task) { Ai::TeamTask.create!(team_execution: exec, description: 'Reviewed', status: 'completed', task_type: 'execution') }
      let!(:rev_ok) do
        Ai::TaskReview.create!(account: account, team_task: task, status: 'approved', review_mode: 'blocking',
          quality_score: 85.0, review_duration_ms: 5000, revision_count: 0,
          findings: [{ 'severity' => 'low', 'category' => 'style', 'description' => 'Minor' }])
      end
      let!(:rev_bad) do
        Ai::TaskReview.create!(account: account, team_task: task, status: 'rejected', review_mode: 'blocking',
          quality_score: 30.0, review_duration_ms: 3000, revision_count: 1,
          findings: [{ 'severity' => 'high', 'category' => 'logic', 'description' => 'Bug' }])
      end
      let!(:rev_pend) { Ai::TaskReview.create!(account: account, team_task: task, status: 'pending', review_mode: 'shadow', quality_score: nil, revision_count: 0) }

      it 'returns counts, approval rate, score distribution, findings, and mode breakdown' do
        quality = service.get_team_analytics(team.id)[:quality]

        expect(quality[:total_reviews]).to eq(3)
        expect(quality[:approved_count]).to eq(1)
        expect(quality[:rejected_count]).to eq(1)
        expect(quality[:pending_count]).to eq(1)
        expect(quality[:approval_rate]).to eq(33.33)
        expect(quality[:quality_score_distribution]).to include('81-100' => 1, '21-40' => 1)
        expect(quality[:findings_by_severity]).to include('low' => 1, 'high' => 1)
        expect(quality[:findings_by_category]).to include('style' => 1, 'logic' => 1)
        expect(quality[:review_mode_breakdown]).to include('blocking' => 2, 'shadow' => 1)
      end
    end

    describe 'quality section - learnings' do
      let!(:l1) do
        Ai::CompoundLearning.create!(account: account, ai_agent_team: team, category: 'pattern',
          scope: 'team', status: 'active', content: 'Retry flaky APIs',
          importance_score: 0.9, confidence_score: 0.8, effectiveness_score: 0.75,
          extraction_method: 'auto_success', injection_count: 10, positive_outcome_count: 8, negative_outcome_count: 2)
      end
      let!(:l2) do
        Ai::CompoundLearning.create!(account: account, ai_agent_team: team, category: 'anti_pattern',
          scope: 'team', status: 'active', content: 'Avoid unbounded loops',
          importance_score: 0.7, confidence_score: 0.6, effectiveness_score: 0.5,
          extraction_method: 'auto_failure', injection_count: 5, positive_outcome_count: 2, negative_outcome_count: 3)
      end

      it 'returns learning counts, categories, injections, and success rate' do
        learning = service.get_team_analytics(team.id)[:quality][:learning]

        expect(learning[:total_learnings]).to eq(2)
        expect(learning[:by_category]).to include('pattern' => 1, 'anti_pattern' => 1)
        expect(learning[:by_extraction_method]).to include('auto_success' => 1, 'auto_failure' => 1)
        expect(learning[:total_injections]).to eq(15)
        expect(learning[:positive_outcomes]).to eq(10)
        expect(learning[:negative_outcomes]).to eq(5)
        expect(learning[:high_importance_count]).to eq(1)
        expect(learning[:injection_success_rate]).to eq(50.0)
      end
    end

    describe 'empty data' do
      it 'returns zeros and empty structures across all sections' do
        result = service.get_team_analytics(team.id)

        overview = result[:overview]
        expect(overview[:total_executions]).to eq(0)
        expect(overview[:success_rate]).to eq(0.0)
        expect(overview[:total_tokens_used]).to eq(0)
        expect(overview[:total_cost_usd]).to eq(0.0)

        perf = result[:performance]
        expect(perf[:avg_duration_ms]).to be_nil
        expect(perf[:median_duration_ms]).to be_nil
        expect(perf[:min_duration_ms]).to be_nil
        expect(perf[:max_duration_ms]).to be_nil

        cost = result[:cost]
        expect(cost[:total_cost_usd]).to eq(0.0)
        expect(cost[:avg_cost_per_execution]).to eq(0)

        learning = result[:quality][:learning]
        expect(learning[:total_learnings]).to eq(0)
        expect(learning[:by_category]).to eq({})
        expect(learning[:injection_success_rate]).to eq(0)
      end
    end

    describe 'period filtering' do
      let!(:recent_exec) do
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed',
          objective: 'Recent', total_tokens_used: 100, total_cost_usd: 0.10,
          started_at: 2.days.ago, completed_at: 1.day.ago, duration_ms: 5000)
      end
      let!(:old_exec) do
        exec = Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed',
          objective: 'Old', total_tokens_used: 9999, total_cost_usd: 99.00,
          started_at: 60.days.ago, completed_at: 59.days.ago, duration_ms: 1000)
        exec.update_columns(created_at: 45.days.ago)
        exec
      end

      it 'excludes old executions with default period and includes them with extended period' do
        result_30 = service.get_team_analytics(team.id, period_days: 30)[:overview]
        expect(result_30[:total_executions]).to eq(1)
        expect(result_30[:total_tokens_used]).to eq(100)

        result_60 = service.get_team_analytics(team.id, period_days: 60)[:overview]
        expect(result_60[:total_executions]).to eq(2)
        expect(result_60[:total_tokens_used]).to eq(10099)
      end
    end

    describe 'percentile edge cases' do
      it 'returns the single value when only one completed execution exists' do
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed',
          objective: 'Solo', duration_ms: 4200, started_at: 2.hours.ago, completed_at: 1.hour.ago)

        perf = service.get_team_analytics(team.id)[:performance]
        expect(perf[:median_duration_ms]).to eq(4200)
        expect(perf[:p95_duration_ms]).to eq(4200)
      end

      it 'computes p95 correctly with two data points' do
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'A', duration_ms: 1000, started_at: 3.hours.ago, completed_at: 2.hours.ago)
        Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'B', duration_ms: 9000, started_at: 2.hours.ago, completed_at: 1.hour.ago)

        perf = service.get_team_analytics(team.id)[:performance]
        expect(perf[:p95_duration_ms]).to eq(9000)
      end
    end
  end
end
