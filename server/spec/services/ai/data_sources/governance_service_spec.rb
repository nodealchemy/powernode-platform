# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DataSources::GovernanceService do
  # ------------------------------------------------------------------
  # Lightweight test doubles (no DB fixtures — class scopes/instances are
  # stubbed per Phase 4b-2b governance test guidance).
  # ------------------------------------------------------------------
  let(:data_source_id) { 'ds-uuid-1' }
  let(:resource_token) { "data_source:#{data_source_id}" }

  # data_source: a Struct/double responding to id, slug, metadata, configuration,
  # account_id. metadata/configuration are plain Hashes.
  def build_data_source(metadata: {}, configuration: {}, id: data_source_id, slug: 'orders-db', account_id: 'acct-1')
    instance_double(
      'Ai::DataSource',
      id: id,
      slug: slug,
      metadata: metadata,
      configuration: configuration,
      account_id: account_id
    )
  end

  let(:data_source) { build_data_source }
  let(:account) { nil }

  # agent: a plain (non-verifying) double responding to id + a trust signal.
  # The real Ai::Agent exposes neither #trust_tier nor #trust_level directly
  # (trust_score is only a has_one association), so the service duck-types via
  # respond_to? — a loose double is the faithful test shape here.
  def build_agent(id: 'agent-1', trust_tier: 'trusted')
    double('Ai::Agent', id: id, trust_tier: trust_tier)
  end

  let(:agent) { build_agent }

  subject(:service) do
    described_class.new(data_source: data_source, agent: agent, account: account)
  end

  # Privilege-policy double — only the surface GovernanceService touches.
  def privilege_policy(denied: [], name: 'priv-policy')
    instance_double(
      'Ai::AgentPrivilegePolicy',
      denied_resources: denied,
      policy_name: name
    )
  end

  # Compliance-policy double.
  def compliance_policy(applies: true, decision: { allowed: true }, blocking: false, name: 'comp-policy')
    instance_double(
      'Ai::CompliancePolicy',
      name: name,
      blocking?: blocking
    ).tap do |dbl|
      allow(dbl).to receive(:applies_to?).and_return(applies)
      allow(dbl).to receive(:evaluate).and_return(decision)
      allow(dbl).to receive(:record_violation!)
    end
  end

  # Stub the CompliancePolicy.active.by_type(...).ordered_by_priority chain.
  def stub_compliance_chain(policies)
    relation = double('compliance_relation')
    allow(Ai::CompliancePolicy).to receive(:active).and_return(relation)
    allow(relation).to receive(:by_type).with('data_access').and_return(relation)
    allow(relation).to receive(:ordered_by_priority).and_return(relation)
    allow(relation).to receive(:to_a).and_return(policies)
    relation
  end

  # Stub AgentPrivilegePolicy.applicable_to(agent_id, tier) => relation w/ to_a.
  def stub_abac(policies, agent_id: 'agent-1', tier: 'trusted')
    relation = double('abac_relation', to_a: policies)
    allow(Ai::AgentPrivilegePolicy)
      .to receive(:applicable_to).with(agent_id, tier).and_return(relation)
    relation
  end

  # ==================================================================
  # #authorize
  # ==================================================================
  describe '#authorize' do
    # ----------------------------------------------------------------
    # ZERO-OVERHEAD SHORT-CIRCUIT
    # ----------------------------------------------------------------
    context 'zero-overhead short-circuit (agent nil AND no governance config)' do
      subject(:service) do
        described_class.new(data_source: build_data_source(metadata: {}), agent: nil, account: account)
      end

      it 'allows without consulting any policy model' do
        expect(Ai::AgentPrivilegePolicy).not_to receive(:applicable_to)
        expect(Ai::CompliancePolicy).not_to receive(:active)

        result = service.authorize(context: {})
        expect(result[:allowed]).to be(true)
      end

      it 'returns a nil reason and nil enforcement on the short-circuit allow' do
        result = service.authorize
        expect(result[:reason]).to be_nil
        expect(result[:enforcement]).to be_nil
      end
    end

    context 'agent nil BUT source has governance config' do
      subject(:service) do
        described_class.new(
          data_source: build_data_source(metadata: { 'governance' => { 'region' => 'eu' } }),
          agent: nil,
          account: account
        )
      end

      it 'does NOT short-circuit — it consults the compliance scope chain' do
        relation = stub_compliance_chain([])
        expect(Ai::CompliancePolicy).to receive(:active).and_return(relation)
        service.authorize
      end

      it 'denies via a blocking compliance policy even with no agent (account-wide enforcement)' do
        policy = compliance_policy(
          applies: true,
          decision: { allowed: false, reason: 'residency', enforcement: 'block' },
          blocking: true
        )
        stub_compliance_chain([policy])
        expect(service.authorize[:allowed]).to be(false)
      end

      it 'skips ABAC (no agent) and allows when no blocking compliance policy applies' do
        expect(Ai::AgentPrivilegePolicy).not_to receive(:applicable_to)
        stub_compliance_chain([])
        expect(service.authorize[:allowed]).to be(true)
      end
    end

    # ----------------------------------------------------------------
    # ABAC (per-agent)
    # ----------------------------------------------------------------
    context 'ABAC with an agent' do
      before { stub_compliance_chain([]) } # keep compliance a no-op for ABAC-focused cases

      it 'denies when an applicable policy lists the resource in denied_resources' do
        policy = privilege_policy(denied: [resource_token], name: 'lockdown')
        stub_abac([policy])

        result = service.authorize
        expect(result[:allowed]).to be(false)
        expect(result[:enforcement]).to eq('block')
      end

      it 'includes the denying policy_name and resource token in the reason' do
        policy = privilege_policy(denied: [resource_token], name: 'lockdown')
        stub_abac([policy])

        result = service.authorize
        expect(result[:reason]).to include('lockdown')
        expect(result[:reason]).to include(resource_token)
      end

      it 'denies (enforcement "block") when an applicable policy denies the wildcard "*"' do
        policy = privilege_policy(denied: ['*'], name: 'deny-all')
        stub_abac([policy])

        result = service.authorize
        expect(result[:allowed]).to be(false)
        expect(result[:enforcement]).to eq('block')
      end

      it 'default-allows (nil reason / nil enforcement) when an applicable policy does NOT mention the resource' do
        policy = privilege_policy(denied: ['data_source:other-id'], name: 'unrelated')
        stub_abac([policy])

        result = service.authorize
        expect(result[:allowed]).to be(true)
        expect(result[:reason]).to be_nil
        expect(result[:enforcement]).to be_nil
      end

      it 'denies if ANY policy in the set explicitly denies (even with permissive others)' do
        permissive = privilege_policy(denied: [], name: 'permissive')
        denier     = privilege_policy(denied: [resource_token], name: 'denier')
        stub_abac([permissive, denier])

        expect(service.authorize[:allowed]).to be(false)
      end

      it 'queries applicable_to with the agent id and resolved trust tier' do
        stub_abac([], tier: 'trusted')
        expect(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).with('agent-1', 'trusted').and_return(double(to_a: []))
        service.authorize
      end
    end

    # ----------------------------------------------------------------
    # COMPLIANCE (residency / consent)
    # ----------------------------------------------------------------
    context 'COMPLIANCE evaluation' do
      before { stub_abac([]) } # ABAC default-allow so we reach compliance

      it 'denies when a blocking, applicable policy evaluates allowed:false' do
        policy = compliance_policy(
          applies: true,
          decision: { allowed: false, reason: 'EU residency required', enforcement: 'block' },
          blocking: true,
          name: 'residency'
        )
        stub_compliance_chain([policy])

        result = service.authorize
        expect(result[:allowed]).to be(false)
      end

      it 'surfaces the decision reason and enforcement on a blocking deny' do
        policy = compliance_policy(
          applies: true,
          decision: { allowed: false, reason: 'EU residency required', enforcement: 'block' },
          blocking: true
        )
        stub_compliance_chain([policy])

        result = service.authorize
        expect(result[:reason]).to eq('EU residency required')
        expect(result[:enforcement]).to eq('block')
      end

      it 'records the violation via #record_violation! on a blocking deny' do
        policy = compliance_policy(
          applies: true,
          decision: { allowed: false, reason: 'blocked' },
          blocking: true
        )
        stub_compliance_chain([policy])

        expect(policy).to receive(:record_violation!).with(
          hash_including(source_type: 'data_source', source_id: data_source_id, severity: 'high')
        )
        service.authorize
      end

      it 'does NOT deny when an applicable policy is NON-blocking (allowed:false but advisory)' do
        policy = compliance_policy(
          applies: true,
          decision: { allowed: false, reason: 'advisory warn' },
          blocking: false
        )
        stub_compliance_chain([policy])

        expect(service.authorize[:allowed]).to be(true)
      end

      it 'does NOT record a violation for a NON-blocking policy' do
        policy = compliance_policy(
          applies: true,
          decision: { allowed: false, reason: 'advisory' },
          blocking: false
        )
        stub_compliance_chain([policy])

        expect(policy).not_to receive(:record_violation!)
        service.authorize
      end

      it 'skips a policy that does NOT apply to the source (applies_to? false)' do
        policy = compliance_policy(
          applies: false,
          decision: { allowed: false, reason: 'would block' },
          blocking: true
        )
        stub_compliance_chain([policy])

        # applies_to? false => evaluate must not even be consulted for a deny
        expect(policy).not_to receive(:record_violation!)
        expect(service.authorize[:allowed]).to be(true)
      end

      it 'stops at the first blocking deny without evaluating later policies' do
        first  = compliance_policy(applies: true, decision: { allowed: false, reason: 'first' }, blocking: true)
        second = compliance_policy(applies: true, decision: { allowed: false, reason: 'second' }, blocking: true)
        stub_compliance_chain([first, second])

        expect(second).not_to receive(:evaluate)
        result = service.authorize
        expect(result[:reason]).to eq('first')
      end

      it 'does not run compliance when ABAC already denied (short-circuits earlier)' do
        # Re-stub ABAC to deny.
        denier = privilege_policy(denied: [resource_token], name: 'abac-deny')
        stub_abac([denier])
        expect(Ai::CompliancePolicy).not_to receive(:active)

        expect(service.authorize[:allowed]).to be(false)
      end
    end

    # ----------------------------------------------------------------
    # FAIL-OPEN vs EXPLICIT DENY
    # ----------------------------------------------------------------
    context 'fail-open on infra error' do
      it 'returns allowed:true when applicable_to RAISES (privilege resolution fault)' do
        allow(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).and_raise(ActiveRecord::StatementInvalid.new('boom'))
        stub_compliance_chain([])

        expect(service.authorize[:allowed]).to be(true)
      end

      it 'logs the error CLASS (not message) on an ABAC infra fault' do
        allow(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).and_raise(ActiveRecord::StatementInvalid.new('secret-detail'))
        stub_compliance_chain([])

        expect(Rails.logger).to receive(:error).with(/ActiveRecord::StatementInvalid/)
        # error message must not be leaked
        expect(Rails.logger).not_to receive(:error).with(/secret-detail/)
        service.authorize
      end

      it 'returns allowed:true when the compliance scope chain RAISES' do
        stub_abac([])
        allow(Ai::CompliancePolicy).to receive(:active).and_raise(StandardError.new('db down'))

        expect(service.authorize[:allowed]).to be(true)
      end

      it 'is distinct from an EXPLICIT deny — an explicit ABAC deny still returns allowed:false' do
        policy = privilege_policy(denied: [resource_token], name: 'explicit')
        stub_abac([policy])
        stub_compliance_chain([])

        expect(service.authorize[:allowed]).to be(false)
      end

      it 'treats a malformed applies_to? (raises) as not-applicable, not a hard fault' do
        stub_abac([])
        policy = compliance_policy(applies: true, decision: { allowed: false, reason: 'x' }, blocking: true)
        allow(policy).to receive(:applies_to?).and_raise(StandardError.new('bad tags'))
        stub_compliance_chain([policy])

        # policy_applies? rescues to false => policy skipped => allow
        expect(service.authorize[:allowed]).to be(true)
      end
    end

    # ----------------------------------------------------------------
    # TRUST TIER RESOLUTION
    # ----------------------------------------------------------------
    context 'trust tier resolution' do
      before { stub_compliance_chain([]) }

      it 'uses agent.trust_tier (string) directly' do
        agent = build_agent(trust_tier: 'autonomous')
        svc = described_class.new(data_source: data_source, agent: agent, account: account)
        expect(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).with('agent-1', 'autonomous').and_return(double(to_a: []))
        svc.authorize
      end

      it 'uses trust_score.tier when trust_score responds to #tier (record)' do
        score = double('Ai::AgentTrustScore', tier: 'monitored')
        # Loose double: responds to id + trust_score, NOT trust_tier/trust_level.
        agent = double('Ai::Agent', id: 'agent-1', trust_score: score)
        svc = described_class.new(data_source: data_source, agent: agent, account: account)

        expect(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).with('agent-1', 'monitored').and_return(double(to_a: []))
        svc.authorize
      end

      it 'maps a numeric trust_score to a tier via TIER_THRESHOLDS (0.95 => autonomous)' do
        agent = double('Ai::Agent', id: 'agent-1', trust_score: 0.95)
        svc = described_class.new(data_source: data_source, agent: agent, account: account)

        expect(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).with('agent-1', 'autonomous').and_return(double(to_a: []))
        svc.authorize
      end

      it 'maps a mid numeric trust_score to "monitored" (0.5 => monitored)' do
        agent = double('Ai::Agent', id: 'agent-1', trust_score: 0.5)
        svc = described_class.new(data_source: data_source, agent: agent, account: account)

        expect(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).with('agent-1', 'monitored').and_return(double(to_a: []))
        svc.authorize
      end

      it 'falls back to "supervised" when the agent exposes no usable trust signal' do
        agent = double('Ai::Agent', id: 'agent-1')
        svc = described_class.new(data_source: data_source, agent: agent, account: account)

        expect(Ai::AgentPrivilegePolicy)
          .to receive(:applicable_to).with('agent-1', 'supervised').and_return(double(to_a: []))
        svc.authorize
      end
    end
  end

  # ==================================================================
  # #mask_records
  # ==================================================================
  describe '#mask_records' do
    let(:sentinel) { 'sensitive-secret-value' }
    let(:redacted) { '[REDACTED]' }

    # Stub the redaction primitive: redact the sentinel, passthrough every other
    # string. The service always calls #redact with keyword args; we capture them
    # via **kwargs (robust across RSpec keyword handling) — log: false is asserted
    # separately in a dedicated example.
    def stub_redaction!
      allow_any_instance_of(Ai::Security::PiiRedactionService)
        .to receive(:redact) do |_receiver, **kwargs|
          text = kwargs[:text]
          if text == sentinel
            { redacted_text: redacted, detections_count: 1, types_found: ['secret'] }
          else
            { redacted_text: text, detections_count: 0, types_found: [] }
          end
        end
    end

    # ----------------------------------------------------------------
    # OFF (passthrough)
    # ----------------------------------------------------------------
    context 'masking OFF' do
      it 'passes through unchanged when there is no governance config' do
        ds = build_data_source(metadata: {})
        svc = described_class.new(data_source: ds, agent: agent, account: account)

        records = [{ 'field' => sentinel }]
        result = svc.mask_records(records)

        expect(result[:masking_applied]).to be(false)
        expect(result[:masked_count]).to eq(0)
        expect(result[:records]).to eq(records)
      end

      it 'passes through when governance exists but neither mask nor mask_at_classification set' do
        ds = build_data_source(metadata: { 'governance' => { 'classification' => 'confidential' } })
        svc = described_class.new(data_source: ds, agent: agent, account: account)

        result = svc.mask_records([{ 'field' => sentinel }])
        expect(result[:masking_applied]).to be(false)
        expect(result[:masked_count]).to eq(0)
      end

      it 'does NOT instantiate the redaction service when masking is off' do
        ds = build_data_source(metadata: {})
        svc = described_class.new(data_source: ds, agent: agent, account: account)

        expect(Ai::Security::PiiRedactionService).not_to receive(:new)
        svc.mask_records([{ 'field' => sentinel }])
      end
    end

    # ----------------------------------------------------------------
    # ON (mask: true)
    # ----------------------------------------------------------------
    context 'masking ON (metadata.governance.mask true)' do
      let(:data_source) { build_data_source(metadata: { 'governance' => { 'mask' => true } }) }
      subject(:service) { described_class.new(data_source: data_source, agent: agent, account: account) }

      before { stub_redaction! }

      it 'redacts a sensitive string VALUE inside a Hash and flags masking_applied' do
        result = service.mask_records([{ 'field' => sentinel }])
        expect(result[:masking_applied]).to be(true)
        expect(result[:records]).to eq([{ 'field' => redacted }])
      end

      it 'counts only the values that actually changed (passthrough strings untouched)' do
        records = [{ 'secret' => sentinel, 'public' => 'harmless' }]
        result = service.mask_records(records)
        expect(result[:masked_count]).to eq(1)
        expect(result[:records]).to eq([{ 'secret' => redacted, 'public' => 'harmless' }])
      end

      it 'deep-walks nested Hashes' do
        records = [{ 'outer' => { 'inner' => sentinel } }]
        result = service.mask_records(records)
        expect(result[:records]).to eq([{ 'outer' => { 'inner' => redacted } }])
        expect(result[:masked_count]).to eq(1)
      end

      it 'walks a mixed Hash/Array structure and masks every sensitive value' do
        records = [
          { 'name' => 'ok', 'creds' => [{ 'token' => sentinel }, { 'token' => sentinel }] }
        ]
        result = service.mask_records(records)
        expect(result[:masked_count]).to eq(2)
        expect(result[:records]).to eq(
          [{ 'name' => 'ok', 'creds' => [{ 'token' => redacted }, { 'token' => redacted }] }]
        )
      end

      it 'does NOT mask Hash KEYS (only values)' do
        # Use the sentinel as a KEY — it must survive unredacted.
        records = [{ sentinel => 'value' }]
        result = service.mask_records(records)
        expect(result[:records]).to eq([{ sentinel => 'value' }])
        expect(result[:masked_count]).to eq(0)
      end

      it 'leaves non-string scalars (Integer, true, nil) untouched alongside a masked value' do
        records = [{ 'count' => 42, 'flag' => true, 'maybe' => nil, 'secret' => sentinel }]
        result = service.mask_records(records)
        expect(result[:records]).to eq(
          [{ 'count' => 42, 'flag' => true, 'maybe' => nil, 'secret' => redacted }]
        )
        expect(result[:masked_count]).to eq(1)
      end

      it 'calls #redact with the string value as :text and log: false (never logs PII)' do
        expect_any_instance_of(Ai::Security::PiiRedactionService)
          .to receive(:redact).with(hash_including(text: sentinel, log: false))
          .and_return({ redacted_text: redacted })
        service.mask_records([sentinel])
      end

      it 'masks a top-level bare string record (not wrapped in a Hash)' do
        result = service.mask_records([sentinel, 'harmless'])
        expect(result[:records]).to eq([redacted, 'harmless'])
        expect(result[:masked_count]).to eq(1)
      end

      it 'returns passthrough metadata when records are blank ([])' do
        result = service.mask_records([])
        expect(result[:masking_applied]).to be(false)
        expect(result[:masked_count]).to eq(0)
        expect(result[:records]).to eq([])
      end

      it 'enables masking via mask_at_classification (not just mask:true)' do
        ds = build_data_source(metadata: { 'governance' => { 'mask_at_classification' => 'confidential' } })
        svc = described_class.new(data_source: ds, agent: agent, account: account)
        stub_redaction!

        result = svc.mask_records([{ 'field' => sentinel }])
        expect(result[:masking_applied]).to be(true)
        expect(result[:records]).to eq([{ 'field' => redacted }])
      end

      it 'instantiates the redaction service exactly once for the whole walk' do
        records = [{ 'a' => sentinel }, { 'b' => sentinel }, { 'c' => sentinel }]
        expect(Ai::Security::PiiRedactionService).to receive(:new).once.and_call_original
        service.mask_records(records)
      end
    end

    # ----------------------------------------------------------------
    # RESCUE — fail safe on availability
    # ----------------------------------------------------------------
    context 'masking error (redact raises)' do
      let(:data_source) { build_data_source(metadata: { 'governance' => { 'mask' => true } }) }
      subject(:service) { described_class.new(data_source: data_source, agent: agent, account: account) }

      it 'returns the ORIGINAL records with masking_applied:false when #redact raises' do
        allow_any_instance_of(Ai::Security::PiiRedactionService)
          .to receive(:redact).and_raise(StandardError.new('redaction engine down'))

        records = [{ 'field' => sentinel }]
        result = service.mask_records(records)

        expect(result[:masking_applied]).to be(false)
        expect(result[:masked_count]).to eq(0)
        expect(result[:records]).to eq(records)
      end

      it 'logs the error CLASS only (never the content) and does not raise to the caller' do
        allow_any_instance_of(Ai::Security::PiiRedactionService)
          .to receive(:redact).and_raise(StandardError.new(sentinel))

        expect(Rails.logger).to receive(:error).with(/StandardError/)
        expect(Rails.logger).not_to receive(:error).with(/#{Regexp.escape(sentinel)}/)
        expect { service.mask_records([{ 'field' => sentinel }]) }.not_to raise_error
      end
    end
  end
end
