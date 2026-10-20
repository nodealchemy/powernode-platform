# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DeferredOperation, type: :model do
  let(:account) { create(:account) }
  let(:chain) do
    Ai::ApprovalChain.create!(
      account: account, name: 'Test', trigger_type: 'autonomy_action',
      status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
      steps: [{ 'name' => 'Step', 'approvers' => ['*'], 'required_approvals' => 1 }]
    )
  end

  before do
    stub_const('TestPerformer', Class.new do
      def self.execute(params, deferred_operation:)
        { performed: true, params: params }
      end

      def self.preview(_params, deferred_operation: nil)
        { summary: 'Test perform' }
      end
    end)
  end

  def make_op(status: 'pending')
    described_class.create!(
      account: account, action_category: 'test.act',
      executor_class: 'TestPerformer',
      status: status, params: { 'k' => 'v' }
    )
  end

  describe 'AASM transitions' do
    it 'starts in pending and can advance through approve → executing → completed' do
      op = make_op
      expect(op.status).to eq('pending')
      op.approve!
      expect(op.status).to eq('approved')
      op.start_execution!
      expect(op.status).to eq('executing')
      op.complete!({ 'result' => 'ok' })
      expect(op.status).to eq('completed')
      expect(op.result).to eq('result' => 'ok')
      expect(op.executed_at).to be_present
    end

    it 'rejects from pending without execution' do
      op = make_op
      op.reject!
      expect(op.status).to eq('rejected')
    end

    it 'fails with error message capture' do
      op = make_op
      op.approve!
      op.start_execution!
      op.fail!(StandardError.new('boom'))
      expect(op.status).to eq('failed')
      expect(op.error_message).to include('boom')
    end
  end

  describe '#execute_now!' do
    it 'transitions through approve → executing → completed and captures result' do
      op = make_op
      result = op.execute_now!
      expect(result).to include(performed: true)
      expect(op.reload.status).to eq('completed')
      expect(op.result).to include('performed' => true)
    end

    it 'masks a secret quoted in the error and message strings of a failed envelope' do
      secret = %w[hunter 2].join
      stub_const('FailedEnvelopeExecutor', Class.new do
        define_singleton_method(:execute) do |_params, deferred_operation:|
          { success: false, error: "db password=#{secret} rejected", message: "token: #{secret}", code: 7 }
        end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'FailedEnvelopeExecutor', params: {}
      )

      op.execute_now!

      result = op.reload.result
      expect(result['error']).to include('[FILTERED]')
      expect(result.to_json).not_to include(secret)
      expect(result['success']).to be(false)
      expect(result['code']).to eq(7)
      expect(op.status).to eq('completed')
    end

    it 'transitions to failed on executor exception' do
      stub_const('FailingExecutor', Class.new do
        def self.execute(_params, deferred_operation:)
          raise 'kaboom'
        end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'FailingExecutor', params: {}
      )
      expect { op.execute_now! }.to raise_error(/kaboom/)
      expect(op.reload.status).to eq('failed')
      expect(op.error_message).to include('kaboom')
    end
  end

  # The gate stores caller-supplied params verbatim
  # (Ai::AutonomyGate#create_deferred_operation!) and replays them here with no
  # re-validation — at approval time, potentially hours later. Executors are
  # intentionally unscoped (ownership is enforced upstream at the call site), so
  # nothing between the request and the executor re-checks that the row the
  # caller named is still one this account may touch.
  describe '#execute_now! tenancy assertion' do
    def op_with_source(source, account: self.account)
      described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'TestPerformer', params: { 'k' => 'v' },
        source_type: source.class.name, source_id: source.id
      )
    end

    it 'refuses to dispatch when the recorded source belongs to another account' do
      dispatched = []
      stub_const('SpyPerformer', Class.new do
        define_singleton_method(:execute) do |_params, deferred_operation:|
          dispatched << deferred_operation.id
          { performed: true }
        end
      end)
      foreign = op_with_source(make_op, account: create(:account))
      op = op_with_source(foreign)
      op.update!(executor_class: 'SpyPerformer')

      # The EFFECT is asserted before the error identity: `raise_error` first
      # would abort the example on the un-fixed code and never print why.
      raised = begin
        op.execute_now!
        nil
      rescue StandardError => e
        e
      end

      expect(dispatched).to be_empty,
                            "the executor ran against another account's record"
      expect(raised).to be_a(described_class::CrossAccountError)
      expect(op.reload.status).to eq('failed')
    end

    # IMP-dae0de4e562b: this used to pin `/#{foreign.id}/` — the refusal NAMED
    # the row it refused. The owner's account id was already withheld (logged,
    # not raised), but naming the source told a caller that the pair they
    # guessed resolves to a real row somewhere, which is the same existence
    # oracle in a different coat. It travels further than the raise, too:
    # #fail! writes "#{e.class}: #{e.message}" to error_message, a column the
    # approvals surface serves back. So the raise now names only the action it
    # refused; the record and its owner stay in the Rails log.
    it 'names the refused action on the failed operation, never the source row' do
      foreign = op_with_source(make_op, account: create(:account))
      op = op_with_source(foreign)

      raised = begin
        op.execute_now!
        nil
      rescue StandardError => e
        e
      end

      expect(raised).to be_a(described_class::CrossAccountError)
      expect(raised.message).to include('test.act')
      expect(raised.message).not_to include(foreign.id),
                                   "the refusal names the row it refused: #{raised.message.inspect}"
      expect(op.reload.error_message).to include('CrossAccountError')
      expect(op.error_message).not_to include(foreign.id),
                                      'the refused row is persisted where the approvals surface serves it'
    end

    it 'keeps the owning account out of the refusal as well' do
      owner = create(:account)
      foreign = op_with_source(make_op, account: owner)
      op = op_with_source(foreign)

      raised = begin
        op.execute_now!
        nil
      rescue StandardError => e
        e
      end

      expect(raised.message).not_to include(owner.id)
    end

    it 'dispatches normally when the recorded source belongs to this account' do
      op = op_with_source(make_op)

      expect(op.execute_now!).to include(performed: true)
      expect(op.reload.status).to eq('completed')
    end

    it 'leaves a source that no longer exists to the executor' do
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'TestPerformer', params: {},
        source_type: 'Ai::DeferredOperation', source_id: SecureRandom.uuid
      )

      expect(op.execute_now!).to include(performed: true)
    end

    # The anchor runs BEFORE the executor, so any raise out of it fails an
    # operation the executor itself would have rejected with a usable message
    # (System::Task, for one, refuses an out-of-list operable_type on
    # validation). Both shapes below are reachable: the source pair on
    # `system.task.*` is the API-supplied operable_type/operable_id, unvalidated
    # at the point the gate records it.
    it 'is a no-op for a source_type that names a class with no table of its own' do
      abstract = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'TestPerformer', params: {},
        source_type: 'ApplicationRecord', source_id: SecureRandom.uuid
      )

      expect(abstract.execute_now!).to include(performed: true)
      expect(abstract.reload.status).to eq('completed')
    end

    it 'is a no-op for a source_type that names a model with no id column' do
      # UserRole is keyed [user_id, role_id]; `find_by(id:)` against it is
      # PG::UndefinedColumn, not a miss.
      keyless = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'TestPerformer', params: {},
        source_type: 'UserRole', source_id: SecureRandom.uuid
      )

      expect(keyless.execute_now!).to include(performed: true)
      expect(keyless.reload.status).to eq('completed')
    end

    # Locks the half that Rails owns rather than this model: OID::Uuid#cast
    # normalises a malformed id to nil (or to canonical form), so `find_by`
    # compiles to `id IS NULL` and no malformed string reaches PostgreSQL —
    # including the shapes the permissive ACCEPTABLE_UUID regex admits. If a
    # future Rails stops casting, it fails here and not on a live operation.
    it 'is a no-op for a malformed source id against a uuid-keyed model' do
      %w[not-a-uuid 1234-5678-1234-1234-1234-1234-5678-9012].each do |malformed|
        malformed_op = described_class.create!(
          account: account, action_category: 'test.act',
          executor_class: 'TestPerformer', params: {},
          source_type: 'Ai::DeferredOperation', source_id: malformed
        )

        expect(malformed_op.execute_now!).to include(performed: true)
        expect(malformed_op.reload.status).to eq('completed')
      end
    end

    # source_type is a free-text column and core cannot know every model an
    # extension gates on, so an unresolvable name must not turn into a raise on
    # a live operation. (The third skip — a resolvable model that exposes no
    # account anchor at all — has no instance among today's source types; it is
    # covered by the guard in #source_account_id, not by an example.)
    it 'is a no-op for a source_type that names no model, and for no source at all' do
      anchorless = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'TestPerformer', params: {},
        source_type: 'NotAModelAtAll', source_id: SecureRandom.uuid
      )

      expect(anchorless.execute_now!).to include(performed: true)
      expect(make_op.execute_now!).to include(performed: true) # no source recorded at all
    end
  end

  describe '#on_approval_decision' do
    let(:request) do
      chain.create_request!(
        source_type: 'Ai::DeferredOperation',
        source_id: SecureRandom.uuid,
        description: 'test',
        request_data: {}
      )
    end

    it 'executes the operation when approval flips to approved' do
      op = make_op
      request.update!(source_id: op.id)
      request.update!(status: 'approved')  # bypass record_decision! for direct test
      op.on_approval_decision(request)
      expect(op.reload.status).to eq('completed')
    end

    it 'rejects the operation when approval flips to rejected' do
      op = make_op
      request.update!(source_id: op.id, status: 'rejected')
      op.on_approval_decision(request)
      expect(op.reload.status).to eq('rejected')
    end

    it 'expires the operation when approval expires' do
      op = make_op
      request.update!(source_id: op.id, status: 'expired')
      op.on_approval_decision(request)
      expect(op.reload.status).to eq('expired')
    end

    it 'is a no-op for already-decided operations (idempotent)' do
      op = make_op
      op.approve!
      op.start_execution!
      op.complete!({})
      request.update!(source_id: op.id, status: 'approved')
      expect { op.on_approval_decision(request) }.not_to change { op.reload.status }
    end
  end

  describe '#preview' do
    it 'returns the executor preview output' do
      op = make_op
      expect(op.preview).to include(summary: 'Test perform')
    end

    # IMP-4a5094b22df0 — the ACCOUNT is what lets an executor anchor an
    # approval card's labels to the account the gate opened the operation in.
    # What crosses the boundary is a PreviewContext, never the operation: see
    # the PreviewContext docstring and the reveal-once isolation spec for why
    # withholding the rest is the guard rather than an omission.
    it 'threads an account-only context into the executor for card anchoring' do
      seen = []
      stub_const('AnchorProbePerformer', Class.new do
        define_singleton_method(:preview) do |_params, deferred_operation: nil|
          seen << deferred_operation
          { summary: 'probed' }
        end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'AnchorProbePerformer', params: {}
      )

      expect(op.preview).to include(summary: 'probed')
      expect(seen.size).to eq(1)
      expect(seen.first).to be_a(described_class::PreviewContext)
      expect(seen.first.account).to eq(account)
    end

    # The withheld half, asserted directly on the object rather than through a
    # card: everything an executor could use to render execution state is
    # absent, so reaching for it raises instead of succeeding quietly.
    it 'hands the executor no execution state to reach for' do
      seen = nil
      stub_const('SurfaceProbePerformer', Class.new do
        define_singleton_method(:preview) do |_params, deferred_operation: nil|
          seen = deferred_operation
          { summary: 'probed' }
        end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'SurfaceProbePerformer', params: { 'k' => 'v' }
      )
      op.preview

      %i[take_revealed_result! result params status executor_class id].each do |leaky|
        expect(seen.respond_to?(leaky, true)).to be(false),
                                                "PreviewContext exposes ##{leaky} to the card path"
      end
    end

    # The keyword is not optional at this call site, so an executor that never
    # accepted it degrades to the rescue arm rather than raising at a caller.
    it 'degrades to the action category for an executor that rejects the keyword' do
      stub_const('LegacyPreviewPerformer', Class.new do
        def self.preview(_params)
          { summary: 'legacy' }
        end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'LegacyPreviewPerformer', params: {}
      )

      expect(op.preview).to include(summary: 'test.act')
    end

    it 'gracefully handles preview exceptions' do
      stub_const('NoPreviewExecutor', Class.new do
        def self.execute(*); end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'NoPreviewExecutor', params: {}
      )
      expect(op.preview).to include(summary: 'test.act')
    end
  end

  # IMP-b44483c3c098 — an executor that MINTS secret material (the federation
  # propose path mints a single-use acceptance token) hands it back in its
  # return value, and #execute_now! persists that value verbatim into the
  # :result jsonb. The proposing operator is meant to see the plaintext exactly
  # once; the row is a durable second copy of it, outside Vault, contradicting
  # the executor's own "only the digest is persisted" contract.
  describe 'secret material in the executor result' do
    let(:minted) { 'MINTED-ACCEPTANCE-TOKEN-PLAINTEXT' }

    before do
      value = minted
      stub_const('TokenMintingPerformer', Class.new do
        define_singleton_method(:execute) do |_params, deferred_operation:|
          { success: true, data: { federation_peer_id: 'peer-42',
                                   acceptance_token_plaintext: value } }
        end

        define_singleton_method(:preview) { |_p, deferred_operation: nil| { summary: 'Propose peer' } }
      end)
    end

    let(:op) do
      described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'TokenMintingPerformer', params: {}
      )
    end

    # The in-process return value is how the proposing operator is shown the
    # token once (Ai::GatedActions renders result.result on the :proceed
    # branch), so it must stay raw.
    it 'returns the plaintext to the in-process caller' do
      expect(op.execute_now!.dig(:data, :acceptance_token_plaintext)).to eq(minted)
    end

    it 'does not persist the plaintext on the row' do
      op.execute_now!

      persisted = described_class.find_by!(id: op.id)
      expect(persisted.result.to_json).not_to include(minted)
      expect(persisted.result.dig('data', 'acceptance_token_plaintext')).to eq('[FILTERED]')
    end

    it 'keeps the rest of the result intact for the auditor who reads the row' do
      op.execute_now!

      persisted = described_class.find_by!(id: op.id)
      expect(persisted.result.dig('data', 'federation_peer_id')).to eq('peer-42')
      expect(persisted.result['success']).to be true
      expect(persisted.status).to eq('completed')
    end
  end

  describe 'secret material in the gated params (IMP-3d10c3c9439e)' do
    let(:secret) { 'HUNTER2-PLAINTEXT-PASSWORD' }
    let(:raw) { { 'username' => 'alice', 'password' => secret, 'opts' => { 'api_key' => 'KEY-PLAINTEXT-1' } } }

    before do
      stub_const('ReplayRecorder', Class.new do
        class << self
          attr_accessor :seen
        end

        def self.execute(params, deferred_operation:)
          self.seen = params
          { success: true }
        end
      end)
    end

    def make_secret_op
      described_class.create!(account: account, action_category: 'test.act',
                              executor_class: 'ReplayRecorder', params: raw)
    end

    it 'never leaves plaintext in the persisted params column' do
      op = make_secret_op

      stored = described_class.connection.select_value(
        "SELECT params::text FROM ai_deferred_operations WHERE id = '#{op.id}'"
      )
      expect(stored).not_to include(secret)
      expect(stored).not_to include('KEY-PLAINTEXT-1')
    end

    it 'serves a redacted params reader that keeps non-secret context' do
      persisted = described_class.find(make_secret_op.id)

      expect(persisted.params['username']).to eq('alice')
      expect(persisted.params['password']).to eq('[FILTERED]')
      expect(persisted.params.dig('opts', 'api_key')).to eq('[FILTERED]')
      expect(persisted.params.to_json).not_to include(secret)
    end

    it 'does not hand the plaintext to an executor preview' do
      seen = nil
      stub_const('PreviewRecorder', Class.new do
        define_singleton_method(:execute) { |_p, deferred_operation:| {} }
        define_singleton_method(:preview) { |p, deferred_operation: nil| seen = p; { summary: 's' } }
      end)
      op = described_class.create!(account: account, action_category: 'test.act',
                                   executor_class: 'PreviewRecorder', params: raw)

      described_class.find(op.id).preview
      expect(seen).to include('username' => 'alice')
      expect(seen.to_json).not_to include(secret)
    end

    it 'replays the original plaintext to the executor after a reload (approval path)' do
      op = described_class.find(make_secret_op.id)

      op.execute_now!

      expect(ReplayRecorder.seen['password']).to eq(secret)
      expect(ReplayRecorder.seen.dig('opts', 'api_key')).to eq('KEY-PLAINTEXT-1')
      expect(ReplayRecorder.seen.keys).not_to include('_sealed_params')
    end

    it 'discards a caller-planted envelope, whatever its key type' do
      op = described_class.create!(account: account, action_category: 'test.act',
                                   executor_class: 'ReplayRecorder', params: { _sealed_params: 'forged', 'k' => 'v' })

      described_class.find(op.id).execute_now!
      expect(ReplayRecorder.seen).to eq('k' => 'v')
    end

    it 'leaves params without secret material untouched' do
      op = make_op
      expect(described_class.find(op.id).params).to eq('k' => 'v')
    end
  end

  describe 'sealing under the house key (IMP-3d10c3c9439e follow-up)' do
    let(:secret) { 'HUNTER2-PLAINTEXT-PASSWORD' }
    let(:raw) { { 'username' => 'alice', 'password' => secret } }

    before do
      stub_const('ReplayRecorder', Class.new do
        class << self
          attr_accessor :seen
        end

        def self.execute(params, deferred_operation:)
          self.seen = params
          { success: true }
        end
      end)
    end

    def make_secret_op(params = raw)
      described_class.create!(account: account, action_category: 'test.act',
                              executor_class: 'ReplayRecorder', params: params)
    end

    def stored_envelope(op)
      described_class.find(op.id)[:params][described_class::SEALED_PARAMS_KEY]
    end

    it 'seals with ActiveRecord::Encryption, so key rotation applies' do
      blob = stored_envelope(make_secret_op)

      plain = ActiveRecord::Encryption.encryptor.decrypt(blob)
      expect(JSON.parse(plain).fetch('params')).to eq(raw)
    end

    it 'masks a legacy row that was written before sealing existed' do
      op = make_op
      described_class.where(id: op.id).update_all([ 'params = ?::jsonb', raw.to_json ])

      legacy = described_class.find(op.id)
      expect(legacy.params).to eq('username' => 'alice', 'password' => '[FILTERED]')
      previewed = nil
      stub_const('LegacyPreviewer', Class.new do
        define_singleton_method(:preview) { |p, deferred_operation: nil| previewed = p; { summary: 's' } }
      end)
      legacy.update_columns(executor_class: 'LegacyPreviewer')
      legacy.reload.preview
      expect(previewed).to eq('username' => 'alice', 'password' => '[FILTERED]')
    end

    it 'raises an explicit error when the envelope is missing its payload' do
      op = make_secret_op
      described_class.where(id: op.id).update_all([ "params = ?::jsonb, status = 'approved'", { 'password' => '[FILTERED]', described_class::SEALED_PARAMS_KEY => '' }.to_json ])
      # a present-but-blank envelope must raise: masked values must NOT replay
      expect { described_class.find(op.id).execute_now! }
        .to raise_error(described_class::SealedParamsError)
    end

    it 'raises an explicit error when the envelope was sealed for another operation' do
      other = described_class.create!(account: account, action_category: 'other.act',
                                      executor_class: 'ReplayRecorder', params: raw)
      op = make_secret_op
      described_class.where(id: op.id).update_all([ "params = ?::jsonb, status = 'approved'", { 'password' => '[FILTERED]', described_class::SEALED_PARAMS_KEY => stored_envelope(other) }.to_json ])

      expect { described_class.find(op.id).execute_now! }
        .to raise_error(described_class::SealedParamsError, /context/)
      expect(ReplayRecorder.seen).to be_nil
    end

    it 'raises an explicit error for an undecryptable envelope' do
      op = make_secret_op
      described_class.where(id: op.id).update_all([ "params = ?::jsonb, status = 'approved'", { 'password' => '[FILTERED]', described_class::SEALED_PARAMS_KEY => 'garbage' }.to_json ])

      expect { described_class.find(op.id).execute_now! }
        .to raise_error(described_class::SealedParamsError)
    end

    it 'drops the in-memory original once the executor has run' do
      op = make_secret_op
      op.execute_now!

      expect(op.instance_variable_get(:@unsealed_params)).to be_nil
    end

    it 'refuses non-Hash params rather than storing them raw' do
      expect { make_secret_op([{ 'password' => secret }]) }
        .to raise_error(ActiveRecord::RecordInvalid, /Params/)
    end

    it 'filters executor exception text before logging it' do
      stub_const('RaisingPerformer', Class.new do
        def self.execute(_params, deferred_operation:)
          raise "boom password=#{'LEAKY-PLAINTEXT'}"
        end
      end)
      op = described_class.create!(account: account, action_category: 'test.act',
                                   executor_class: 'RaisingPerformer', params: {})
      logged = []
      allow(Rails.logger).to receive(:error) { |msg| logged << msg }

      expect { op.execute_now! }.to raise_error(RuntimeError)
      expect(logged.join).not_to include('LEAKY-PLAINTEXT')
    end

    describe 'replaying rows that carry no envelope' do
      def unsealed_op(params, status: 'approved')
        op = make_op
        described_class.where(id: op.id).update_all([ 'params = ?::jsonb, status = ?', params.to_json, status ])
        described_class.where(id: op.id).update_all(executor_class: 'ReplayRecorder')
        described_class.find(op.id)
      end

      it 'replays the raw column of a legacy plaintext row, not the masked view' do
        unsealed_op(raw).execute_now!

        expect(ReplayRecorder.seen).to eq(raw)
      end

      it 'replays the raw value when the operator later widens the sensitive keys' do
        op = unsealed_op({ 'custom_field' => 'real-value' })
        allow(SiteSetting).to receive(:get).and_call_original
        allow(SiteSetting).to receive(:get).with('ai_sensitive_param_keys').and_return([ 'custom_field' ])

        op.execute_now!
        expect(ReplayRecorder.seen).to eq('custom_field' => 'real-value')
      end
    end

    it 'filters the exception text persisted by fail!' do
      op = make_op(status: 'approved')
      op.fail!(RuntimeError.new('boom password=LEAKY-PLAINTEXT'))

      expect(op.reload.error_message).not_to include('LEAKY-PLAINTEXT')
    end

    it 'filters the preview failure text' do
      stub_const('BadPreviewer', Class.new do
        def self.preview(_params, deferred_operation: nil)
          raise 'bad password=LEAKY-PLAINTEXT'
        end
      end)
      op = described_class.create!(account: account, action_category: 'test.act',
                                   executor_class: 'BadPreviewer', params: {})

      expect(op.preview[:error]).not_to include('LEAKY-PLAINTEXT')
    end

    describe 'raw replay edges' do
      it 'refuses to replay a live row whose envelope was stripped and left masked values' do
        op = make_secret_op
        described_class.where(id: op.id).update_all(
          [ "params = ?::jsonb, status = 'approved'", { 'username' => 'alice', 'password' => '[FILTERED]' }.to_json ]
        )

        expect { described_class.find(op.id).execute_now! }.to raise_error(described_class::SealedParamsError)
        expect(ReplayRecorder.seen).to be_nil
      end

      it 'strips a planted envelope key of any key type from the raw replay' do
        op = described_class.new(account: account, action_category: 'test.act', executor_class: 'ReplayRecorder')

        expect(op.send(:raw_params, { :_sealed_params => 'planted', 'k' => 'v' })).to eq('k' => 'v')
      end
    end

    describe '.backfill_params_seal extras' do
      def legacy_op(status)
        op = make_op
        described_class.where(id: op.id).update_all([ 'params = ?::jsonb, status = ?', raw.to_json, status ])
        op
      end

      it 'is a no-op on a second applied run' do
        legacy_op('pending')
        legacy_op('completed')
        described_class.backfill_params_seal(dry_run: false)

        expect(described_class.backfill_params_seal(dry_run: false)).to include(sealed: 0, masked: 0)
      end

      it 'seals an executing row' do
        op = legacy_op('executing')
        described_class.backfill_params_seal(dry_run: false)

        expect(described_class.find(op.id)[:params]).to have_key(described_class::SEALED_PARAMS_KEY)
      end

      it 're-seals live sealed rows under the current key, dry run by default' do
        op = make_secret_op
        before_blob = stored_envelope(op)

        counts = described_class.backfill_params_seal(reseal: true)
        expect(counts).to include(resealed: 1, dry_run: true)
        expect(stored_envelope(op)).to eq(before_blob)

        described_class.backfill_params_seal(dry_run: false, reseal: true)
        expect(stored_envelope(op)).not_to eq(before_blob)
        op = described_class.find(op.id)
        op.update_columns(status: 'approved')
        op.execute_now!
        expect(ReplayRecorder.seen).to eq(raw)
      end

      it 'moves envelopes onto the new key so the old key can be dropped' do
        keys = ->(*list) { ActiveRecord::Encryption::DerivedSecretKeyProvider.new(list) }
        old_key = 'o' * 32
        new_key = 'n' * 32
        op = ActiveRecord::Encryption.with_encryption_context(key_provider: keys.call(old_key)) { make_secret_op }

        ActiveRecord::Encryption.with_encryption_context(key_provider: keys.call(old_key, new_key)) do
          described_class.backfill_params_seal(dry_run: false, reseal: true)
        end

        op = described_class.find(op.id)
        op.update_columns(status: 'approved')
        ActiveRecord::Encryption.with_encryption_context(key_provider: keys.call(new_key)) do
          op.execute_now!
        end
        expect(ReplayRecorder.seen).to eq(raw)
      end

      it 'counts an undecryptable envelope as failed and still re-seals the rest, in dry run too' do
        good = make_secret_op
        bad = make_secret_op
        described_class.where(id: bad.id).update_all(
          [ 'params = ?::jsonb', { 'password' => '[FILTERED]', described_class::SEALED_PARAMS_KEY => 'garbage' }.to_json ]
        )
        good_blob = stored_envelope(good)

        dry = described_class.backfill_params_seal(reseal: true)
        expect(dry).to include(failed: 1, resealed: 1, dry_run: true)
        expect(stored_envelope(good)).to eq(good_blob)

        applied = described_class.backfill_params_seal(dry_run: false, reseal: true)
        expect(applied).to include(failed: 1, resealed: 1)
        expect(stored_envelope(good)).not_to eq(good_blob)
      end

      it 'does not re-seal terminal sealed rows' do
        op = make_secret_op
        op.update_columns(status: 'completed')

        expect(described_class.backfill_params_seal(reseal: true)).to include(resealed: 0)
      end
    end

    describe '.backfill_params_seal' do
      def legacy_op(status)
        op = make_op
        described_class.where(id: op.id).update_all([ 'params = ?::jsonb, status = ?', raw.to_json, status ])
        op
      end

      it 'is a dry run by default and reports counts without writing' do
        legacy_op('pending')
        legacy_op('completed')

        counts = described_class.backfill_params_seal
        expect(counts).to include(sealed: 1, masked: 1, dry_run: true)
        expect(described_class.pluck(:params).to_json).to include(secret)
      end

      it 'seals live rows and only masks terminal ones when applied' do
        live = legacy_op('pending')
        done = legacy_op('completed')

        described_class.backfill_params_seal(dry_run: false)

        expect(described_class.pluck(:params).to_json).not_to include(secret)
        expect(described_class.find(live.id).send(:replay_params)).to eq(raw)
        expect(described_class.find(done.id)[:params]).not_to have_key(described_class::SEALED_PARAMS_KEY)
      end
    end
  end
end
