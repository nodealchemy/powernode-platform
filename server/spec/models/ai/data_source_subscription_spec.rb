# frozen_string_literal: true

require 'rails_helper'

# Phase 3 — pull-based subscription cadence + poll-outcome bookkeeping.
#
# Ai::DataSourceSubscription mirrors Ai::DataConnector's sync cadence but drives
# the server-side Ai::DataSources::MonitorService loop. These specs pin the
# behaviour the monitor relies on:
#   - before_create seeds next_poll_at for any non-manual cadence (so a sub is
#     pollable the moment it is created, without an explicit activate!);
#   - schedule_next_poll! advances next_poll_at by the per-frequency interval;
#   - .due_for_poll INCLUDES status "error" (the documented self-heal path) and
#     EXCLUDES operator-set "paused";
#   - record_poll! resets the failure counter, clears error -> active, updates the
#     change fingerprint, and reschedules;
#   - record_failure! increments the counter, trips "error" at the 5th failure,
#     and STILL reschedules so a transient fault self-heals.
#
# HERMETIC: the subscription factory creates an Ai::DataSource, whose
# after_commit :sync_to_knowledge_graph fires under transactional tests and would
# otherwise reach the embedding backend. We neutralise the embedding-backed KG
# bridge for every create in this file (the DatabaseCleaner :deletion gotcha).
# The subscription model itself has no KG/embedding callbacks.
RSpec.describe Ai::DataSourceSubscription, type: :model do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }

  # Neutralise the embedding-backed KG sync triggered by creating a data source.
  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService)
      .to receive(:sync_data_source).and_return(nil)
  end

  # Build (not create) so cadence-seeding callbacks can be exercised per-example.
  def build_subscription(**attrs)
    build(:ai_data_source_subscription, { data_source: data_source, endpoint: endpoint }.merge(attrs))
  end

  def create_subscription(**attrs)
    create(:ai_data_source_subscription, { data_source: data_source, endpoint: endpoint }.merge(attrs))
  end

  describe 'associations' do
    subject { build_subscription }

    it { is_expected.to belong_to(:data_source).class_name('Ai::DataSource').with_foreign_key('ai_data_source_id') }
    it { is_expected.to belong_to(:endpoint).class_name('Ai::DataSourceEndpoint').with_foreign_key('ai_data_source_endpoint_id') }
    it { is_expected.to belong_to(:agent).class_name('Ai::Agent').with_foreign_key('ai_agent_id').optional }
  end

  describe 'validations' do
    subject { build_subscription }

    it { is_expected.to be_valid }

    it { is_expected.to validate_presence_of(:ai_data_source_id) }
    it { is_expected.to validate_presence_of(:ai_data_source_endpoint_id) }

    it 'allows every supported poll_frequency' do
      described_class::POLL_FREQUENCIES.each do |freq|
        candidate = build_subscription(poll_frequency: freq)
        expect(candidate).to be_valid, "expected #{freq} to be a valid poll_frequency"
      end
    end

    it 'rejects an unknown poll_frequency' do
      subject.poll_frequency = 'every_other_tuesday'
      expect(subject).not_to be_valid
      expect(subject.errors[:poll_frequency]).to be_present
    end

    it 'allows a nil poll_frequency' do
      subject.poll_frequency = nil
      expect(subject).to be_valid
    end

    it 'allows every supported status' do
      described_class::STATUSES.each do |status|
        expect(build_subscription(status: status)).to be_valid, "expected #{status} to be a valid status"
      end
    end

    it 'rejects an unknown status' do
      subject.status = 'sleeping'
      expect(subject).not_to be_valid
      expect(subject.errors[:status]).to be_present
    end

    it 'rejects a negative consecutive_failures' do
      subject.consecutive_failures = -1
      expect(subject).not_to be_valid
      expect(subject.errors[:consecutive_failures]).to be_present
    end
  end

  describe 'JSON column defaults' do
    it 'defaults params and metadata to empty hashes on a new record' do
      sub = described_class.new
      expect(sub.params).to eq({})
      expect(sub.metadata).to eq({})
    end
  end

  # --- Cadence seeding (before_create) -------------------------------------
  describe 'before_create cadence seeding' do
    it 'seeds next_poll_at on create for a non-manual cadence' do
      sub = create_subscription(poll_frequency: 'hourly', next_poll_at: nil)
      expect(sub.next_poll_at).to be_present
      expect(sub.next_poll_at).to be_within(5.seconds).of(Time.current)
    end

    it 'seeds next_poll_at for the realtime cadence' do
      sub = create_subscription(poll_frequency: 'realtime', next_poll_at: nil)
      expect(sub.next_poll_at).to be_present
    end

    it 'leaves next_poll_at nil for a manual cadence' do
      sub = create_subscription(poll_frequency: 'manual', next_poll_at: nil)
      expect(sub.next_poll_at).to be_nil
    end

    it 'leaves next_poll_at nil when poll_frequency is blank' do
      sub = create_subscription(poll_frequency: nil, next_poll_at: nil)
      expect(sub.next_poll_at).to be_nil
    end

    it 'does not overwrite an explicitly supplied next_poll_at' do
      explicit = 2.days.from_now.change(usec: 0)
      sub = create_subscription(poll_frequency: 'daily', next_poll_at: explicit)
      expect(sub.next_poll_at).to be_within(1.second).of(explicit)
    end
  end

  # --- poll_interval -------------------------------------------------------
  describe '#poll_interval' do
    {
      'realtime' => 0.seconds,
      '5min' => 5.minutes,
      'hourly' => 1.hour,
      'daily' => 1.day,
      'weekly' => 1.week,
      'monthly' => 1.month
    }.each do |freq, duration|
      it "returns #{duration.inspect} for #{freq}" do
        expect(build_subscription(poll_frequency: freq).poll_interval).to eq(duration)
      end
    end

    it 'returns an ActiveSupport::Duration' do
      expect(build_subscription(poll_frequency: 'hourly').poll_interval).to be_a(ActiveSupport::Duration)
    end

    it 'falls back to 1 hour for manual (used only when forced to schedule)' do
      expect(build_subscription(poll_frequency: 'manual').poll_interval).to eq(1.hour)
    end
  end

  # --- schedule_next_poll! -------------------------------------------------
  describe '#schedule_next_poll!' do
    it 'advances next_poll_at by the cadence interval (5min)' do
      sub = create_subscription(poll_frequency: '5min')
      freeze_time do
        sub.schedule_next_poll!
        expect(sub.next_poll_at).to be_within(1.second).of(Time.current + 5.minutes)
      end
    end

    it 'advances next_poll_at by the cadence interval (daily)' do
      sub = create_subscription(poll_frequency: 'daily')
      freeze_time do
        sub.schedule_next_poll!
        expect(sub.next_poll_at).to be_within(1.second).of(Time.current + 1.day)
      end
    end

    it 'schedules realtime immediately (interval 0)' do
      sub = create_subscription(poll_frequency: 'realtime')
      freeze_time do
        sub.schedule_next_poll!
        expect(sub.next_poll_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'never schedules a manual cadence (leaves next_poll_at nil)' do
      sub = create_subscription(poll_frequency: 'manual')
      expect(sub.next_poll_at).to be_nil
      sub.schedule_next_poll!
      expect(sub.reload.next_poll_at).to be_nil
    end

    it 'never schedules a blank cadence' do
      sub = create_subscription(poll_frequency: nil)
      sub.schedule_next_poll!
      expect(sub.reload.next_poll_at).to be_nil
    end

    it 'persists the new next_poll_at' do
      sub = create_subscription(poll_frequency: 'hourly')
      freeze_time do
        sub.schedule_next_poll!
        expect(sub.reload.next_poll_at).to be_within(1.second).of(Time.current + 1.hour)
      end
    end
  end

  # --- .due_for_poll (CRITICAL auto-recovery guard) ------------------------
  describe '.due_for_poll' do
    # next_poll_at is set directly so the before_create seeder / schedule cannot
    # reseed it out from under the boundary assertions.
    def with_poll_at(sub, time)
      sub.update_column(:next_poll_at, time)
      sub
    end

    it 'INCLUDES an overdue ACTIVE subscription' do
      sub = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'active'), 1.minute.ago)
      expect(described_class.due_for_poll).to include(sub)
    end

    # The auto-recovery guard: an errored + overdue sub MUST still be selected so
    # record_poll! can clear it back to active. Excluding it would strand the sub
    # in "error" forever.
    it 'INCLUDES an overdue ERROR subscription (self-heal path)' do
      sub = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'error'), 1.minute.ago)
      expect(described_class.due_for_poll).to include(sub)
    end

    it 'EXCLUDES a PAUSED subscription even when overdue' do
      sub = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'paused'), 1.minute.ago)
      expect(described_class.due_for_poll).not_to include(sub)
    end

    it 'EXCLUDES an active subscription whose next_poll_at is in the future' do
      sub = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'active'), 1.hour.from_now)
      expect(described_class.due_for_poll).not_to include(sub)
    end

    it 'EXCLUDES a subscription with a nil next_poll_at (e.g. manual)' do
      sub = create_subscription(poll_frequency: 'manual', status: 'active', next_poll_at: nil)
      expect(described_class.due_for_poll).not_to include(sub)
    end

    it 'INCLUDES a subscription due exactly now (<= boundary is inclusive)' do
      sub = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'active'), Time.current)
      expect(described_class.due_for_poll).to include(sub)
    end

    it 'returns active and error rows together, omitting paused' do
      active = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'active'), 1.minute.ago)
      errored = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'error'), 1.minute.ago)
      paused = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'paused'), 1.minute.ago)

      due = described_class.due_for_poll
      expect(due).to include(active, errored)
      expect(due).not_to include(paused)
    end
  end

  describe '.active' do
    it 'returns only active subscriptions' do
      active = create_subscription(status: 'active')
      create_subscription(status: 'paused')
      create_subscription(status: 'error')
      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe '.for_data_source / .for_endpoint' do
    it 'scopes to a data source by record and by id' do
      mine = create_subscription
      other_ds = create(:ai_data_source, account: account)
      other_ep = create(:ai_data_source_endpoint, data_source: other_ds)
      create_subscription(data_source: other_ds, endpoint: other_ep)

      expect(described_class.for_data_source(data_source)).to contain_exactly(mine)
      expect(described_class.for_data_source(data_source.id)).to contain_exactly(mine)
    end

    it 'scopes to an endpoint by record and by id' do
      mine = create_subscription
      other_ep = create(:ai_data_source_endpoint, data_source: data_source)
      create_subscription(endpoint: other_ep)

      expect(described_class.for_endpoint(endpoint)).to contain_exactly(mine)
      expect(described_class.for_endpoint(endpoint.id)).to contain_exactly(mine)
    end
  end

  # --- record_poll! --------------------------------------------------------
  describe '#record_poll!' do
    it 'stamps last_polled_at and resets consecutive_failures to 0' do
      sub = create_subscription(poll_frequency: 'hourly', consecutive_failures: 3)
      freeze_time do
        sub.record_poll!(changed: true)
        sub.reload
        expect(sub.last_polled_at).to be_within(1.second).of(Time.current)
        expect(sub.consecutive_failures).to eq(0)
      end
    end

    it 'clears an error status back to active on a successful poll' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'error', consecutive_failures: 6)
      sub.record_poll!(changed: false)
      expect(sub.reload.status).to eq('active')
      expect(sub.consecutive_failures).to eq(0)
    end

    it 'leaves an already-active subscription active' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active')
      sub.record_poll!(changed: true)
      expect(sub.reload.status).to eq('active')
    end

    it 'updates last_checksum and last_etag when supplied' do
      sub = create_subscription(poll_frequency: 'hourly')
      sub.record_poll!(changed: true, checksum: 'abc123', etag: 'W/"v1"')
      sub.reload
      expect(sub.last_checksum).to eq('abc123')
      expect(sub.last_etag).to eq('W/"v1"')
    end

    it 'does not clobber an existing checksum/etag when not supplied' do
      sub = create_subscription(poll_frequency: 'hourly', last_checksum: 'keep', last_etag: 'keep-etag')
      sub.record_poll!(changed: false)
      sub.reload
      expect(sub.last_checksum).to eq('keep')
      expect(sub.last_etag).to eq('keep-etag')
    end

    it 'reschedules the next poll by the cadence interval' do
      sub = create_subscription(poll_frequency: 'hourly')
      freeze_time do
        sub.record_poll!(changed: true)
        expect(sub.reload.next_poll_at).to be_within(1.second).of(Time.current + 1.hour)
      end
    end

    it 'returns the changed flag it was given' do
      sub = create_subscription(poll_frequency: 'hourly')
      expect(sub.record_poll!(changed: true)).to be(true)
      expect(sub.record_poll!(changed: false)).to be(false)
    end
  end

  # --- record_failure! -----------------------------------------------------
  describe '#record_failure!' do
    it 'increments consecutive_failures and returns the new count' do
      sub = create_subscription(poll_frequency: 'hourly', consecutive_failures: 0)
      expect(sub.record_failure!).to eq(1)
      expect(sub.reload.consecutive_failures).to eq(1)
    end

    it 'stays active below the failure threshold' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active', consecutive_failures: 3)
      sub.record_failure!
      expect(sub.reload.status).to eq('active')
      expect(sub.consecutive_failures).to eq(4)
    end

    it 'flips to error on the 5th consecutive failure' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active', consecutive_failures: 4)
      sub.record_failure!
      sub.reload
      expect(sub.consecutive_failures).to eq(5)
      expect(sub.status).to eq('error')
    end

    it 'keeps incrementing past the threshold while remaining in error' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'error', consecutive_failures: 7)
      sub.record_failure!
      sub.reload
      expect(sub.consecutive_failures).to eq(8)
      expect(sub.status).to eq('error')
    end

    it 'still reschedules the next poll so a transient fault self-heals' do
      sub = create_subscription(poll_frequency: 'hourly')
      freeze_time do
        sub.record_failure!('boom')
        expect(sub.reload.next_poll_at).to be_within(1.second).of(Time.current + 1.hour)
      end
    end

    it 'does NOT reschedule when the subscription is paused' do
      # next_poll_at is forced to nil AFTER create because the before_create seeder
      # ignores status and would otherwise stamp a non-manual cadence. The point of
      # this spec is that record_failure! leaves a paused sub's schedule alone.
      sub = create_subscription(poll_frequency: 'hourly', status: 'paused')
      sub.update_column(:next_poll_at, nil)
      sub.record_failure!('boom')
      expect(sub.reload.next_poll_at).to be_nil
    end

    it 'records the error message and timestamp in metadata' do
      sub = create_subscription(poll_frequency: 'hourly')
      freeze_time do
        sub.record_failure!('upstream 503')
        sub.reload
        expect(sub.metadata['last_error']).to eq('upstream 503')
        expect(sub.metadata['last_error_at']).to eq(Time.current.iso8601)
      end
    end

    it 'leaves metadata untouched when no error message is given' do
      sub = create_subscription(poll_frequency: 'hourly', metadata: { 'keep' => 'me' })
      sub.record_failure!
      expect(sub.reload.metadata).to eq('keep' => 'me')
    end

    it 'stamps last_polled_at' do
      sub = create_subscription(poll_frequency: 'hourly')
      freeze_time do
        sub.record_failure!
        expect(sub.reload.last_polled_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  # --- needs_poll? ---------------------------------------------------------
  describe '#needs_poll?' do
    it 'is true for an active subscription whose next_poll_at is in the past' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active')
      sub.update_column(:next_poll_at, 1.minute.ago)
      expect(sub.needs_poll?).to be(true)
    end

    it 'is true exactly at the boundary (<= now)' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active')
      freeze_time do
        sub.update_column(:next_poll_at, Time.current)
        expect(sub.needs_poll?).to be(true)
      end
    end

    it 'is false when next_poll_at is in the future' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active')
      sub.update_column(:next_poll_at, 1.hour.from_now)
      expect(sub.needs_poll?).to be(false)
    end

    it 'is false when next_poll_at is nil' do
      sub = create_subscription(poll_frequency: 'manual', status: 'active', next_poll_at: nil)
      expect(sub.needs_poll?).to be(false)
    end

    it 'is false when the subscription is paused even if overdue' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'paused')
      sub.update_column(:next_poll_at, 1.minute.ago)
      expect(sub.needs_poll?).to be(false)
    end

    it 'is false when the subscription is in error (needs_poll? is active-only)' do
      # NOTE: due_for_poll INCLUDES error rows, but needs_poll? is a stricter
      # per-record active-only check — the two are intentionally different.
      sub = create_subscription(poll_frequency: 'hourly', status: 'error')
      sub.update_column(:next_poll_at, 1.minute.ago)
      expect(sub.needs_poll?).to be(false)
    end
  end

  # --- activate! / pause! / active? ----------------------------------------
  describe '#activate!' do
    it 'sets status to active and schedules the next poll' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'paused', next_poll_at: nil)
      freeze_time do
        sub.activate!
        sub.reload
        expect(sub.status).to eq('active')
        expect(sub.next_poll_at).to be_within(1.second).of(Time.current + 1.hour)
      end
    end

    it 'does not schedule a manual cadence on activate' do
      sub = create_subscription(poll_frequency: 'manual', status: 'paused', next_poll_at: nil)
      sub.activate!
      sub.reload
      expect(sub.status).to eq('active')
      expect(sub.next_poll_at).to be_nil
    end
  end

  describe '#pause!' do
    it 'sets status to paused and clears next_poll_at' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'active')
      sub.pause!
      sub.reload
      expect(sub.status).to eq('paused')
      expect(sub.next_poll_at).to be_nil
    end
  end

  describe '#active?' do
    it 'is true only for the active status' do
      expect(build_subscription(status: 'active').active?).to be(true)
      expect(build_subscription(status: 'paused').active?).to be(false)
      expect(build_subscription(status: 'error').active?).to be(false)
    end
  end

  # --- 4b-1: sync_cursor opt-in high-watermark via record_poll!(cursor:) -----
  # The incremental high-watermark follows the SAME opt-in semantics as
  # last_checksum / last_etag: record_poll! advances sync_cursor only when a
  # present cursor is supplied; a nil or blank cursor leaves the stored watermark
  # untouched so a "no-change" poll never resets incremental progress.
  describe '#record_poll! sync_cursor' do
    it 'sets sync_cursor to the supplied cursor on a changed poll (and keeps the existing success contract)' do
      sub = create_subscription(poll_frequency: 'hourly', status: 'error', consecutive_failures: 4)
      freeze_time do
        sub.record_poll!(changed: true, cursor: 'c1')
        sub.reload
        expect(sub.sync_cursor).to eq('c1')
        # Existing record_poll! contract still holds alongside the cursor write.
        expect(sub.consecutive_failures).to eq(0)
        expect(sub.last_polled_at).to be_within(1.second).of(Time.current)
        expect(sub.status).to eq('active')
        expect(sub.next_poll_at).to be_within(1.second).of(Time.current + 1.hour)
      end
    end

    it 'advances an existing sync_cursor to a new value when supplied' do
      sub = create_subscription(poll_frequency: 'hourly')
      sub.update_column(:sync_cursor, 'cursor-baseline')
      sub.record_poll!(changed: true, cursor: 'cursor-next')
      expect(sub.reload.sync_cursor).to eq('cursor-next')
    end

    it 'leaves an existing sync_cursor untouched when called with NO cursor (opt-in)' do
      sub = create_subscription(poll_frequency: 'hourly')
      sub.update_column(:sync_cursor, 'keep-me')
      sub.record_poll!(changed: false)
      expect(sub.reload.sync_cursor).to eq('keep-me')
    end

    it 'does not clobber an existing sync_cursor with a blank cursor: ""' do
      sub = create_subscription(poll_frequency: 'hourly')
      sub.update_column(:sync_cursor, 'keep-me')
      sub.record_poll!(changed: true, cursor: '')
      expect(sub.reload.sync_cursor).to eq('keep-me')
    end

    it 'does not clobber an existing sync_cursor with an explicit nil cursor' do
      sub = create_subscription(poll_frequency: 'hourly')
      sub.update_column(:sync_cursor, 'cursor-baseline')
      sub.record_poll!(changed: false, cursor: nil)
      expect(sub.reload.sync_cursor).to eq('cursor-baseline')
    end

    it 'leaves sync_cursor nil when none has ever been supplied' do
      sub = create_subscription(poll_frequency: 'hourly')
      sub.record_poll!(changed: false)
      expect(sub.reload.sync_cursor).to be_nil
    end
  end

  # --- 4b-1: due_for_poll includes error status (auto-recovery) -------------
  # Re-pinned at the cadence level: an errored + overdue subscription MUST be
  # returned by .due_for_poll so the monitor can re-poll it — record_poll! is the
  # ONLY transition that clears error -> active, so excluding errored rows would
  # strand the subscription in "error" forever. Operator-set "paused" stays out.
  describe '.due_for_poll auto-recovery of error status' do
    def with_poll_at(sub, time)
      sub.update_column(:next_poll_at, time)
      sub
    end

    it 'returns a due ERROR subscription, a due ACTIVE one, but NOT a due PAUSED one' do
      errored = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'error'), 1.minute.ago)
      active  = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'active'), 1.minute.ago)
      paused  = with_poll_at(create_subscription(poll_frequency: 'hourly', status: 'paused'), 1.minute.ago)

      due = described_class.due_for_poll
      expect(due).to include(errored)
      expect(due).to include(active)
      expect(due).not_to include(paused)
    end

    it 'transitions an ERROR subscription back to active when record_poll! runs (closing the loop)' do
      sub = with_poll_at(
        create_subscription(poll_frequency: 'hourly', status: 'error', consecutive_failures: 6),
        1.minute.ago
      )
      # Confirm the monitor would actually pick it up before recovering it.
      expect(described_class.due_for_poll).to include(sub)

      sub.record_poll!(changed: false)
      sub.reload
      expect(sub.status).to eq('active')
      expect(sub.consecutive_failures).to eq(0)
    end
  end
end
