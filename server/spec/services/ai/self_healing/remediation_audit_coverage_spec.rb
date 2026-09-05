# frozen_string_literal: true

require 'rails_helper'

# The audit trail for self-healing remediations, and the mechanical link that
# stops it drifting again.
#
# Ai::RemediationLog::ACTION_TYPES is an allow-list in one file enumerating
# values produced in another, with nothing connecting them. It drifted: the
# dispatcher grew model_downgrade and context_trim, the allow-list did not, so
# log_remediation's create! failed its inclusion validation and the bare rescue
# swallowed it. The two most state-changing remediations executed with no audit
# row at all, and the only trace was a log line saying the log had failed.
#
# The examples below derive the produced set from the producers' OWN source and
# reflection rather than restating it, so the NEXT remediation added without an
# audit type reds here instead of going silent in production.
RSpec.describe 'self-healing remediation audit coverage' do
  DISPATCHER_SOURCE = Rails.root.join('app/services/ai/self_healing/remediation_dispatcher.rb')
  MONITOR_SOURCE = Rails.root.join('app/services/ai/self_healing/predictive_monitor_service.rb')

  # A method's source text, from its `def` up to the next `def` in the file.
  # Deliberately not a hand-copied list: the point of these guards is that they
  # read what the producer actually says today.
  # NB: the indent classes are [ \t], not \s — \s matches newlines, which lets
  # the "next def" probe match the method's own def line at offset 0 and hand
  # back an empty body that scans to [] and silently passes a containment check.
  def method_source(path, name)
    src = File.read(path)
    offset = src.index(/^[ \t]*def #{Regexp.escape(name)}\b/)
    raise "could not locate ##{name} in #{path}" if offset.nil?

    rest = src[offset..]
    following_def = rest.index(/\n[ \t]*def /)
    following_def ? rest[0...following_def] : rest
  end

  # The context shapes that steer the producers down each of their branches.
  BRANCH_CONTEXTS = [
    {},
    { service_type: 'provider' },
    { service_type: 'cache' }
  ].freeze

  describe 'every remediation the dispatcher can EXECUTE is auditable' do
    # Derived from the dispatcher's own executor methods. `execute_<action>` is
    # how an action becomes real, so this set is the set of things that can
    # mutate state, whatever the trigger table happens to say.
    let(:executable_actions) do
      Ai::SelfHealing::RemediationDispatcher
        .singleton_class
        .private_instance_methods(false)
        .grep(/\Aexecute_/)
        .map { |m| m.to_s.delete_prefix('execute_') }
        .reject { |name| name == 'action' } # execute_action is the dispatcher, not an action
    end

    it 'finds the executors (guard is live, not vacuous)' do
      expect(executable_actions)
        .to include('provider_failover', 'model_downgrade', 'context_trim', 'alert_escalation')
    end

    it 'has an Ai::RemediationLog action_type for each one' do
      expect(executable_actions - Ai::RemediationLog::ACTION_TYPES).to be_empty
    end
  end

  describe 'every action determine_action can RETURN is auditable' do
    # Scanned from determine_action's own `when` clauses.
    let(:trigger_events) do
      method_source(DISPATCHER_SOURCE, 'determine_action').scan(/when "([a-z_]+)"/).flatten
    end

    let(:produced_actions) do
      trigger_events.flat_map { |event|
        BRANCH_CONTEXTS.map do |context|
          Ai::SelfHealing::RemediationDispatcher.send(:determine_action, event, context)
        end
      }.compact.uniq
    end

    it 'finds the trigger events it branches on (guard is live, not vacuous)' do
      expect(trigger_events)
        .to include('circuit_breaker_opened', 'execution_degradation', 'context_overflow')
    end

    it 'reaches the two actions that drifted' do
      expect(produced_actions).to include('model_downgrade', 'context_trim')
    end

    it 'produces only action types RemediationLog will accept' do
      expect(produced_actions - Ai::RemediationLog::ACTION_TYPES).to be_empty
    end
  end

  describe 'every action the predictive monitor can HINT is auditable' do
    # The action_hint path bypasses determine_action's case statement entirely
    # (remediation_dispatcher.rb: `return context[:action_hint] if
    # context[:preemptive] && context[:action_hint]`), so it is a second,
    # independent producer of action_type and needs its own guard.
    let(:monitor) { Ai::SelfHealing::PredictiveMonitorService.new(account: nil) }

    let(:event_types) do
      method_source(MONITOR_SOURCE, 'determine_preemptive_action').scan(/when "([a-z_]+)"/).flatten
    end

    let(:hinted_actions) do
      signal_shapes = [nil, ['latency_spike_3.0x'], ['error_rate_50pct']]

      event_types.flat_map { |event_type|
        signal_shapes.map do |signals|
          monitor.send(:determine_preemptive_action, { event_type: event_type, signals: signals })
        end
      }.compact.uniq
    end

    it 'finds the event types it branches on (guard is live, not vacuous)' do
      expect(event_types).to include('provider_degradation', 'execution_degradation', 'cost_anomaly')
    end

    it 'reaches the model_downgrade hint' do
      expect(hinted_actions).to include('model_downgrade')
    end

    it 'hints only action types RemediationLog will accept' do
      expect(hinted_actions - Ai::RemediationLog::ACTION_TYPES).to be_empty
    end
  end

  describe 'an unauditable action is refused rather than executed unlogged' do
    let(:account) { create(:account) }
    let!(:primary) { create(:ai_provider, :openai, account: account) }
    let!(:backup) { create(:ai_provider, :openai, account: account, name: 'OpenAI Backup', slug: 'openai-backup') }
    let!(:backup_credential) { create(:ai_provider_credential, account: account, provider: backup) }
    let!(:agent) { create(:ai_agent, account: account, ai_provider_id: primary.id, status: 'active') }

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
      allow(Ai::RemediationLog).to receive(:hourly_count).and_return(0)

      # provider_failover is deliberately NOT auditable for this example. Using a
      # real action type rather than a nonsense one is what makes the assertion
      # meaningful: the executor exists and would move the agent.
      stub_const('Ai::RemediationLog::ACTION_TYPES', %w[alert_escalation])
    end

    def dispatch
      Ai::SelfHealing::RemediationDispatcher.dispatch(
        account: account,
        trigger_source: 'predictive_monitor',
        trigger_event: 'provider_degradation',
        context: { provider_id: primary.id }
      )
    end

    it 'does not mutate agent state' do
      expect { dispatch }.not_to change { agent.reload.ai_provider_id }
    end

    it 'does not call the executor' do
      expect(Ai::SelfHealing::RemediationDispatcher).not_to receive(:execute_provider_failover)

      dispatch
    end

    it 'writes no remediation log (there is no type it could be written under)' do
      expect { dispatch }.not_to change(Ai::RemediationLog, :count)
    end

    it 'records the refusal where an operator can see it' do
      expect(Rails.logger).to receive(:error).with(/Refusing unauditable remediation/)

      dispatch
    end
  end

  describe 'context_trim is audited end to end' do
    let(:account) { create(:account) }
    let(:provider) { create(:ai_provider, :anthropic, account: account) }
    let!(:agent) { create(:ai_agent, account: account, provider: provider, status: 'active') }
    let!(:execution) { create(:ai_agent_execution, account: account, agent: agent, provider: provider) }

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
      allow(Ai::RemediationLog).to receive(:hourly_count).and_return(0)
    end

    def dispatch
      Ai::SelfHealing::RemediationDispatcher.dispatch(
        account: account,
        trigger_source: 'agent_execution',
        trigger_event: 'context_overflow',
        context: { execution_id: execution.id }
      )
    end

    # A failing remediation is what the audit fix is worth: before it, an
    # executor raised, execute_action's rescue turned that into result:
    # "failure", and log_remediation's create! then failed the inclusion
    # validation and was swallowed — a remediation failing completely silently.
    #
    # The executor is stubbed to raise rather than allowed to raise for real:
    # a real DB-level failure aborts the surrounding test transaction and makes
    # the subsequent audit INSERT impossible to observe. Production has no such
    # transaction.
    it 'records a failed attempt instead of losing it' do
      allow(Ai::SelfHealing::RemediationDispatcher)
        .to receive(:execute_context_trim).and_raise(StandardError, 'short-term memory query blew up')

      expect { dispatch }.to change(Ai::RemediationLog, :count).by(1)

      log = Ai::RemediationLog.order(:executed_at).last
      expect(log.action_type).to eq('context_trim')
      expect(log.result).to eq('failure')
      expect(log.result_message).to eq('short-term memory query blew up')
      expect(log.account_id).to eq(account.id)
      expect(log.trigger_event).to eq('context_overflow')
      expect(log.executed_at).to be_present
    end

    # REPLACES the KNOWN GAP example that pinned the raise. The query is now
    # repaired — and repaired by DELEGATION to Ai::Memory::MaintenanceService
    # #cleanup_expired, the seam that already owns expired-STM deletion — so
    # these assert the OBSERVABLE outcome the acceptance criteria asked for:
    # the reachable short-term memory set is measurably smaller afterwards, and
    # an audit row records it. "Did not raise" would be the same oracle that let
    # the original defect hide.
    it 'deletes the expired rows and keeps the unexpired ones' do
      fresh = Ai::AgentShortTermMemory.create!(
        account: account, agent: agent, session_id: 'ctx-trim-guard',
        memory_key: 'fresh', memory_value: { 'v' => 1 }, ttl_seconds: 3600,
        expires_at: 1.hour.from_now
      )
      stale = Ai::AgentShortTermMemory.create!(
        account: account, agent: agent, session_id: 'ctx-trim-guard',
        memory_key: 'stale', memory_value: { 'v' => 2 }, ttl_seconds: 3600,
        expires_at: 1.hour.ago
      )

      expect { dispatch }
        .to change { Ai::AgentShortTermMemory.for_agent(agent.id).count }.from(2).to(1)

      expect(Ai::AgentShortTermMemory.exists?(fresh.id)).to be(true)
      expect(Ai::AgentShortTermMemory.exists?(stale.id)).to be(false)
    end

    it 'audits the trim with the count it actually removed' do
      2.times do |i|
        Ai::AgentShortTermMemory.create!(
          account: account, agent: agent, session_id: 'ctx-trim-audit',
          memory_key: "stale-#{i}", memory_value: { 'v' => i }, ttl_seconds: 3600,
          expires_at: 1.hour.ago
        )
      end

      expect { dispatch }.to change(Ai::RemediationLog, :count).by(1)

      log = Ai::RemediationLog.order(:executed_at).last
      expect(log.action_type).to eq('context_trim')
      expect(log.result).to eq('success')
      expect(log.result_message).to include('Trimmed 2 short-term memory rows')
      expect(log.result_message).to include('2 -> 0 reachable')
      expect(log.trigger_event).to eq('context_overflow')
    end

    # The trim delegates rather than carrying its own copy of the query. Pinned
    # because a future edit that inlines the query here would silently fork from
    # the maintenance pass and drift — which is how the original wrong-column
    # query came to exist in the first place.
    it 'delegates to the maintenance seam rather than querying directly' do
      maintenance = instance_double(Ai::Memory::MaintenanceService)
      expect(Ai::Memory::MaintenanceService)
        .to receive(:new).with(account: account).and_return(maintenance)
      expect(maintenance).to receive(:cleanup_expired).with(agent: agent).and_return({ deleted: 7 })

      dispatch

      expect(Ai::RemediationLog.order(:executed_at).last.result_message)
        .to include('Trimmed 7 short-term memory rows')
    end

    # The column names the original defect got wrong. The KNOWN GAP example was
    # the only assertion in the tree pinning them; the repair removed it, so the
    # fact it rested on is re-pinned here. Add an `is_active` column later and
    # this reds, which is the moment the executor's comment needs re-reading.
    it 'still describes the schema the repaired query is written against' do
      expect(Ai::AgentShortTermMemory.column_names).to include('agent_id', 'expires_at')
      expect(Ai::AgentShortTermMemory.column_names).not_to include('ai_agent_id', 'is_active')
    end
  end
end
