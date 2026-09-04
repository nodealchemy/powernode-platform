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

    # A failing context_trim is what this fix is worth: before it, the executor
    # raised, execute_action's rescue turned that into result: "failure", and
    # log_remediation's create! then failed the inclusion validation and was
    # swallowed — a remediation that can NEVER work, failing completely silently.
    #
    # The executor is stubbed to raise rather than allowed to raise for real: the
    # real failure is a PG error, which aborts the surrounding test transaction
    # and makes the subsequent audit INSERT impossible to observe. Production has
    # no such transaction. The real raise is pinned separately below.
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

    # KNOWN GAP, deliberately pinned and NOT fixed here (out of this task's
    # scope; filed for its own task, the way IMP-929aadc88e19 was filed for the
    # sibling defect in execute_model_downgrade). execute_context_trim queries
    # Ai::AgentShortTermMemory on `ai_agent_id` and `is_active`; the table has
    # `agent_id` and no active flag at all, so every context_trim raises before
    # it trims anything. Nothing surfaced because the audit row it would have
    # failed under was itself being dropped — this example is the record that the
    # capability is inert, and it reds when someone repairs the query.
    it 'KNOWN GAP: the executor raises on columns ai_agent_short_term_memories does not have' do
      expect(Ai::AgentShortTermMemory.column_names).to include('agent_id')
      expect(Ai::AgentShortTermMemory.column_names).not_to include('ai_agent_id', 'is_active')

      expect {
        Ai::SelfHealing::RemediationDispatcher.send(
          :execute_context_trim, account, { execution_id: execution.id }
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /ai_agent_id|is_active/)
    end
  end
end
