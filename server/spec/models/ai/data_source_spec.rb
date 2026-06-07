# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DataSource, type: :model do
  let(:account) { create(:account) }

  subject(:data_source) { build(:ai_data_source, account: account) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }

    it 'has many credentials destroyed with the source' do
      is_expected.to have_many(:credentials)
        .class_name('Ai::DataSourceCredential')
        .with_foreign_key('ai_data_source_id')
        .dependent(:destroy)
    end

    it 'has many endpoints destroyed with the source' do
      is_expected.to have_many(:endpoints)
        .class_name('Ai::DataSourceEndpoint')
        .with_foreign_key('ai_data_source_id')
        .dependent(:destroy)
    end

    it 'has many queries destroyed with the source' do
      is_expected.to have_many(:queries)
        .class_name('Ai::DataSourceQuery')
        .with_foreign_key('ai_data_source_id')
        .dependent(:destroy)
    end
  end

  describe 'validations' do
    it { is_expected.to be_valid }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:source_type) }

    it { is_expected.to validate_inclusion_of(:source_type).in_array(described_class::SOURCE_TYPES) }

    it 'validates name uniqueness within an account (case-insensitive)' do
      create(:ai_data_source, account: account, name: 'NOAA Feed')
      dup = build(:ai_data_source, account: account, name: 'noaa feed')
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to include('has already been taken')
    end

    it 'allows the same name across different accounts' do
      create(:ai_data_source, account: account, name: 'NOAA Feed')
      other = build(:ai_data_source, account: create(:account), name: 'NOAA Feed')
      expect(other).to be_valid
    end

    it 'requires priority_order to be greater than zero' do
      data_source.priority_order = 0
      expect(data_source).not_to be_valid
      expect(data_source.errors[:priority_order]).to be_present
    end

    it 'validates health_status inclusion but allows nil' do
      data_source.health_status = 'on_fire'
      expect(data_source).not_to be_valid

      data_source.health_status = nil
      expect(data_source).to be_valid
    end
  end

  describe 'slug auto-generation' do
    it 'derives a slug from the name on create' do
      ds = create(:ai_data_source, account: account, name: 'Open Meteo', slug: nil)
      expect(ds.slug).to eq('open_meteo')
    end

    it 'disambiguates duplicate slugs within the same account' do
      first = create(:ai_data_source, account: account, name: 'Weather', slug: nil)
      second = create(:ai_data_source, account: account, name: 'Weather!', slug: nil)
      expect(first.slug).to eq('weather')
      expect(second.slug).to eq('weather_1')
    end
  end

  # --- JSON column defaults -------------------------------------------------
  #
  # REGRESSION: auth_config must default to {} on a brand-new record. The
  # column is declared with a lambda default in the model; a bare DB default
  # of `{}` (without the attribute lambda) would surface as nil on an
  # in-memory record and break auth-scheme config reads. We assert against a
  # plain `.new` (not the factory, which sets auth_config explicitly) so this
  # exercises the model attribute default, not the factory value.
  describe 'auth_config default' do
    it 'defaults to an empty hash on a new (unpersisted) record' do
      expect(described_class.new.auth_config).to eq({})
    end

    it 'still defaults to {} when other attributes are supplied' do
      ds = described_class.new(name: 'X', source_type: 'custom')
      expect(ds.auth_config).to eq({})
    end

    it 'round-trips an explicit auth_config through persistence' do
      ds = create(:ai_data_source, account: account, auth_config: { 'region' => 'us-east-1' })
      expect(ds.reload.auth_config).to eq({ 'region' => 'us-east-1' })
    end
  end

  describe 'other JSON column defaults' do
    it 'defaults collection columns to empty containers' do
      ds = described_class.new
      expect(ds.capabilities).to eq([])
      expect(ds.configuration).to eq({})
      expect(ds.rate_limits).to eq({})
      expect(ds.default_parameters).to eq({})
      expect(ds.metadata).to eq({})
    end
  end

  # --- Quota counters (Redis round-trip) -----------------------------------
  #
  # REGRESSION (guards the just-fixed `Redis.current` blocker): #record_request!
  # must actually increment counters on `Powernode::Redis.client`, and
  # #current_quota_usage must read those same counters back. We use the real
  # shared client so the increment + read-back path is exercised end-to-end
  # (a message-verifying double would not have caught the `Redis.current`
  # NameError, since the methods rescue StandardError and silently no-op).
  describe 'quota tracking via Redis' do
    let(:data_source) { create(:ai_data_source, account: account) }

    # Wipe this source's quota keys before and after so the round-trip starts
    # from a known-zero baseline and leaves no residue for other specs.
    def quota_keys(redis)
      redis.keys("data_source:#{data_source.id}:quota:*")
    end

    around do |example|
      redis =
        begin
          Powernode::Redis.client.tap(&:ping)
        rescue StandardError
          nil
        end

      skip 'Redis is not reachable for the quota round-trip regression' if redis.nil?

      keys = quota_keys(redis)
      redis.del(*keys) unless keys.empty?
      begin
        example.run
      ensure
        residue = quota_keys(redis)
        redis.del(*residue) unless residue.empty?
      end
    end

    it 'starts at zero before any request is recorded' do
      expect(data_source.current_quota_usage).to eq(
        minute: 0, hour: 0, day: 0, bandwidth_today: 0
      )
    end

    it 'increments minute/hour/day counters that current_quota_usage reads back' do
      3.times { data_source.record_request! }

      usage = data_source.current_quota_usage
      expect(usage[:minute]).to eq(3)
      expect(usage[:hour]).to eq(3)
      expect(usage[:day]).to eq(3)
    end

    it 'writes the counters to the shared Powernode::Redis client keys' do
      data_source.record_request!

      redis = Powernode::Redis.client
      now = Time.current
      prefix = "data_source:#{data_source.id}:quota"
      minute_key = "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}"

      # Read the raw key straight off the same client record_request! used.
      expect(redis.get(minute_key).to_i).to eq(1)
    end

    it 'accumulates bandwidth when bytes are provided' do
      data_source.record_request!(bytes: 512)
      data_source.record_request!(bytes: 488)

      expect(data_source.current_quota_usage[:bandwidth_today]).to eq(1000)
    end

    it 'does not record bandwidth when bytes are zero' do
      data_source.record_request!(bytes: 0)
      expect(data_source.current_quota_usage[:bandwidth_today]).to eq(0)
    end

    it 'sets a TTL on the counter keys' do
      data_source.record_request!

      redis = Powernode::Redis.client
      now = Time.current
      minute_key = "data_source:#{data_source.id}:quota:min:#{now.strftime('%Y%m%d%H%M')}"

      expect(redis.ttl(minute_key)).to be > 0
    end
  end

  # --- check_quota! against recorded usage ---------------------------------
  describe '#check_quota!' do
    it 'allows requests when no rate limits are configured' do
      ds = build(:ai_data_source, account: account, rate_limits: {})
      expect(ds.check_quota!).to eq(allowed: true)
    end

    it 'denies once recorded usage meets the per-minute limit' do
      ds = create(:ai_data_source, account: account,
                  rate_limits: { 'requests_per_minute' => 2 })

      allow(ds).to receive(:current_quota_usage).and_return(
        minute: 2, hour: 2, day: 2, bandwidth_today: 0
      )

      result = ds.check_quota!
      expect(result[:allowed]).to be(false)
      expect(result[:limit]).to eq('requests_per_minute')
      expect(result[:retry_after]).to be_a(Integer)
    end

    it 'allows when usage is below the configured limit' do
      ds = create(:ai_data_source, account: account,
                  rate_limits: { 'requests_per_minute' => 60 })

      allow(ds).to receive(:current_quota_usage).and_return(
        minute: 1, hour: 1, day: 1, bandwidth_today: 0
      )

      expect(ds.check_quota!).to eq(allowed: true)
    end
  end

  describe 'scopes' do
    it '.active returns only active sources' do
      live = create(:ai_data_source, account: account, is_active: true)
      create(:ai_data_source, account: account, is_active: false)
      expect(described_class.active).to include(live)
      expect(described_class.active).to all(have_attributes(is_active: true))
    end

    it '.by_type filters by source_type' do
      noaa = create(:ai_data_source, account: account, source_type: 'noaa_ncei')
      create(:ai_data_source, account: account, source_type: 'custom')
      expect(described_class.by_type('noaa_ncei')).to contain_exactly(noaa)
    end

    it '.requiring_auth returns sources that require auth' do
      secured = create(:ai_data_source, :requires_auth, account: account)
      create(:ai_data_source, account: account, requires_auth: false)
      expect(described_class.requiring_auth).to contain_exactly(secured)
    end

    it '.ordered_by_priority orders ascending by priority_order' do
      low = create(:ai_data_source, account: account, priority_order: 10, slug: nil)
      high = create(:ai_data_source, account: account, priority_order: 5, slug: nil)
      expect(described_class.ordered_by_priority.to_a).to eq([high, low])
    end
  end

  describe 'helpers' do
    describe '#to_param' do
      it 'returns the slug' do
        ds = create(:ai_data_source, account: account, name: 'FRED', slug: nil)
        expect(ds.to_param).to eq('fred')
      end
    end

    describe '#healthy?' do
      it 'is true for an active source with healthy/unknown status' do
        expect(build(:ai_data_source, is_active: true, health_status: 'healthy')).to be_healthy
        expect(build(:ai_data_source, is_active: true, health_status: 'unknown')).to be_healthy
      end

      it 'is false when inactive or in a bad state' do
        expect(build(:ai_data_source, is_active: false, health_status: 'healthy')).not_to be_healthy
        expect(build(:ai_data_source, is_active: true, health_status: 'critical')).not_to be_healthy
      end
    end
  end

  # --- Phase 2a: effectiveness scoring ------------------------------------
  #
  # These specs cover the rolled-up scoring counters + effectiveness blend
  # added in Phase 2a. They share a stubbed KG bridge so the after_commit
  # :sync_to_knowledge_graph hook (which DOES fire under transactional tests
  # in Rails) is a no-op unless a spec is specifically asserting against it —
  # mirroring spec/services/ai/skill_graph/bridge_service_spec.rb. Where a
  # spec needs to observe sync calls it overrides the stub with a spy.
  describe 'effectiveness scoring (Phase 2a)' do
    # By default, neutralize the embedding-backed KG sync entirely so create/
    # update don't try to reach an embedding backend. Counter-bump specs then
    # assert sync_data_source is NOT re-invoked on top of this baseline.
    before do
      allow_any_instance_of(Ai::DataSourceGraph::BridgeService)
        .to receive(:sync_data_source).and_return(nil)
    end

    describe '#record_query!' do
      let(:data_source) { create(:ai_data_source, account: account) }

      it 'increments usage_count and the positive counter on success' do
        data_source.record_query!(outcome: 'success')
        data_source.reload

        expect(data_source.usage_count).to eq(1)
        expect(data_source.positive_usage_count).to eq(1)
        expect(data_source.negative_usage_count).to eq(0)
      end

      it 'increments usage_count and the negative counter on failure' do
        data_source.record_query!(outcome: 'failure')
        data_source.reload

        expect(data_source.usage_count).to eq(1)
        expect(data_source.positive_usage_count).to eq(0)
        expect(data_source.negative_usage_count).to eq(1)
      end

      it 'treats any non-"success" outcome as a failure for the counters' do
        data_source.record_query!(outcome: 'error')
        data_source.reload

        expect(data_source.positive_usage_count).to eq(0)
        expect(data_source.negative_usage_count).to eq(1)
      end

      it 'stamps last_used_at on each recorded query' do
        freeze_at = Time.current
        travel_to(freeze_at) { data_source.record_query!(outcome: 'success') }

        expect(data_source.reload.last_used_at).to be_within(1.second).of(freeze_at)
      end

      it 'accumulates counters across multiple queries' do
        2.times { data_source.record_query!(outcome: 'success') }
        data_source.record_query!(outcome: 'failure')
        data_source.reload

        expect(data_source.usage_count).to eq(3)
        expect(data_source.positive_usage_count).to eq(2)
        expect(data_source.negative_usage_count).to eq(1)
      end

      # The counter bump is a single update_columns write that deliberately
      # bypasses the Auditable after_update callback (no per-bump audit row)
      # AND the after_commit KG re-sync (the embedding doesn't depend on
      # counters). update_columns skips BOTH callback chains.
      context 'callback isolation (hot fetch path)' do
        it 'does not invoke the Auditable update audit callback' do
          # Auditable#log_record_update is the after_update hook. update_columns
          # never fires it; a plain update! would. (In test env the hook also
          # early-returns, so we assert on the callback method itself, which is
          # the real bypass mechanism — not on AuditLog rows.)
          expect(data_source).not_to receive(:log_record_update)
          data_source.record_query!(outcome: 'success')
        end

        it 'creates no AuditLog rows for a counter bump' do
          expect { data_source.record_query!(outcome: 'success') }
            .not_to change(AuditLog, :count)
        end

        it 'does not re-trigger the knowledge-graph sync bridge on a counter bump' do
          # Materialize the lazy let FIRST so the baseline create's after_commit
          # sync runs before we arm the negative mock — otherwise that legitimate
          # one-time sync is miscounted against not_to-receive.
          data_source
          expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
            .not_to receive(:sync_data_source)
          data_source.record_query!(outcome: 'success')
        end
      end

      describe 'recalculate cadence (every 5th query)' do
        it 'does not recalc before the 5th outcome' do
          expect(data_source).not_to receive(:recalculate_effectiveness!)
          4.times { data_source.record_query!(outcome: 'success') }
        end

        it 'recalculates on exactly the 5th outcome' do
          4.times { data_source.record_query!(outcome: 'success') }

          expect(data_source).to receive(:recalculate_effectiveness!).once
          data_source.record_query!(outcome: 'success')
        end

        it 'recalculates again on the 10th outcome' do
          recalc_calls = 0
          allow(data_source).to receive(:recalculate_effectiveness!) { recalc_calls += 1 }

          10.times { data_source.record_query!(outcome: 'success') }

          expect(recalc_calls).to eq(2)
        end

        it 'passes the per-query freshness override through to the recalc' do
          4.times { data_source.record_query!(outcome: 'success') }

          expect(data_source).to receive(:recalculate_effectiveness!).with(freshness: 0.9)
          data_source.record_query!(outcome: 'success', freshness: 0.9)
        end
      end
    end

    describe '#recalculate_effectiveness!' do
      # freshness is supplied explicitly here so the score is fully determined
      # by kg_confidence + usage_success_rate and we don't depend on wall-clock
      # recency decay (that is covered separately under #freshness_score).
      it 'blends 0.3*kg_confidence + 0.4*success_rate + 0.3*freshness' do
        node = create(:ai_knowledge_graph_node, :data_source_node,
                      account: account, confidence: 0.8)
        ds = create(:ai_data_source, account: account,
                    positive_usage_count: 3, negative_usage_count: 1)
        node.update_columns(ai_data_source_id: ds.id)

        ds.recalculate_effectiveness!(freshness: 1.0)

        # 0.3*0.8 + 0.4*0.75 + 0.3*1.0 = 0.24 + 0.30 + 0.30 = 0.84
        expect(ds.reload.effectiveness_score).to eq(0.84)
      end

      it 'defaults kg_confidence to 0.5 when there is no linked KG node' do
        ds = create(:ai_data_source, account: account,
                    positive_usage_count: 1, negative_usage_count: 1)

        ds.recalculate_effectiveness!(freshness: 0.0)

        # 0.3*0.5 + 0.4*0.5 + 0.3*0.0 = 0.15 + 0.20 + 0.0 = 0.35
        expect(ds.reload.effectiveness_score).to eq(0.35)
      end

      it 'rounds the blended score to 4 decimal places' do
        node = create(:ai_knowledge_graph_node, :data_source_node,
                      account: account, confidence: 0.3333)
        ds = create(:ai_data_source, account: account,
                    positive_usage_count: 1, negative_usage_count: 2)
        node.update_columns(ai_data_source_id: ds.id)

        ds.recalculate_effectiveness!(freshness: 0.1)

        # success_rate = 1/3 = 0.3333; 0.3*0.3333 + 0.4*0.3333 + 0.3*0.1
        expected = (0.3 * 0.3333 + 0.4 * 0.3333 + 0.3 * 0.1).round(4)
        expect(ds.reload.effectiveness_score).to eq(expected)
      end

      it 'clamps an out-of-range freshness override into 0..1' do
        ds = create(:ai_data_source, account: account,
                    positive_usage_count: 2, negative_usage_count: 0)

        ds.recalculate_effectiveness!(freshness: 5.0)

        # freshness clamped to 1.0: 0.3*0.5 + 0.4*1.0 + 0.3*1.0 = 0.85
        expect(ds.reload.effectiveness_score).to eq(0.85)
      end

      it 'writes via update_columns (no audit callback, no KG re-sync)' do
        ds = create(:ai_data_source, account: account,
                    positive_usage_count: 1, negative_usage_count: 0)

        expect(ds).not_to receive(:log_record_update)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .not_to receive(:sync_data_source)

        ds.recalculate_effectiveness!(freshness: 0.5)
      end
    end

    describe '#usage_success_rate' do
      it 'is the neutral 0.5 when no outcomes are recorded yet' do
        ds = build(:ai_data_source, account: account,
                   positive_usage_count: 0, negative_usage_count: 0)
        expect(ds.usage_success_rate).to eq(0.5)
      end

      it 'is positives over total, rounded to 4 dp' do
        ds = build(:ai_data_source, account: account,
                   positive_usage_count: 3, negative_usage_count: 1)
        expect(ds.usage_success_rate).to eq(0.75)
      end

      it 'is 1.0 when every recorded outcome succeeded' do
        ds = build(:ai_data_source, account: account,
                   positive_usage_count: 4, negative_usage_count: 0)
        expect(ds.usage_success_rate).to eq(1.0)
      end

      it 'is 0.0 when every recorded outcome failed' do
        ds = build(:ai_data_source, account: account,
                   positive_usage_count: 0, negative_usage_count: 5)
        expect(ds.usage_success_rate).to eq(0.0)
      end
    end

    # freshness_score is private; exercised via recalculate_effectiveness!
    # with no freshness override, which derives the freshness signal from
    # recency. We isolate freshness by forcing kg_confidence and success_rate
    # to known neutral 0.5 values, so effectiveness = 0.65*0.5 + 0.3*freshness
    # ... actually 0.3*0.5 + 0.4*0.5 + 0.3*fresh = 0.35 + 0.3*fresh, letting us
    # back out the freshness component the model computed.
    describe 'freshness_score (7-day linear decay, via #recalculate_effectiveness!)' do
      def freshness_from(ds)
        # No KG node -> kg_confidence 0.5; no outcomes -> success_rate 0.5.
        ds.recalculate_effectiveness!
        ((ds.reload.effectiveness_score - 0.35) / 0.3).round(4)
      end

      it 'defaults to 0.5 when never used or health-checked' do
        ds = create(:ai_data_source, account: account,
                    last_used_at: nil, last_health_check_at: nil)
        expect(freshness_from(ds)).to eq(0.5)
      end

      it 'is ~1.0 immediately after use (fresh)' do
        ds = create(:ai_data_source, account: account, last_used_at: Time.current)
        expect(freshness_from(ds)).to be_within(0.01).of(1.0)
      end

      it 'decays toward ~0.5 around the midpoint of the 7-day window' do
        ds = create(:ai_data_source, account: account,
                    last_used_at: 3.5.days.ago, last_health_check_at: nil)
        expect(freshness_from(ds)).to be_within(0.02).of(0.5)
      end

      it 'floors at 0.0 once the source is a full week stale' do
        ds = create(:ai_data_source, account: account,
                    last_used_at: 8.days.ago, last_health_check_at: nil)
        expect(freshness_from(ds)).to eq(0.0)
      end

      it 'uses the most recent of last_used_at / last_health_check_at' do
        # Stale use, but a very recent health check -> should read as fresh.
        ds = create(:ai_data_source, account: account,
                    last_used_at: 30.days.ago, last_health_check_at: Time.current)
        expect(freshness_from(ds)).to be_within(0.01).of(1.0)
      end
    end
  end

  # --- has_one :knowledge_graph_node + guarded after_commit sync -----------
  describe 'knowledge graph integration' do
    describe 'association' do
      it 'has one knowledge_graph_node, nullified (not destroyed) with the source' do
        is_expected.to have_one(:knowledge_graph_node)
          .class_name('Ai::KnowledgeGraphNode')
          .with_foreign_key('ai_data_source_id')
          .dependent(:nullify)
      end
    end

    describe 'after_commit :sync_to_knowledge_graph guard' do
      # Spy on the bridge so we can assert exactly when a re-embed is triggered.
      # We do NOT stub it here (the real method degrades without an embedding
      # backend), but we still want to count calls deterministically, so we
      # stub it to a no-op and inspect invocation.
      before do
        allow_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .to receive(:sync_data_source).and_return(nil)
      end

      it 'fires on create (initial node build)' do
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .to receive(:sync_data_source).once
        create(:ai_data_source, account: account)
      end

      it 'fires when the name changes' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .to receive(:sync_data_source).once
        ds.update!(name: 'Renamed Source')
      end

      it 'fires when the description changes' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .to receive(:sync_data_source).once
        ds.update!(description: 'A fresh description')
      end

      it 'fires when the source_type changes' do
        ds = create(:ai_data_source, account: account, source_type: 'custom')
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .to receive(:sync_data_source).once
        ds.update!(source_type: 'open_meteo')
      end

      it 'fires when the slug changes' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .to receive(:sync_data_source).once
        ds.update!(slug: 'a-new-slug')
      end

      it 'does NOT fire on a counter-only update (record_query!)' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .not_to receive(:sync_data_source)
        ds.record_query!(outcome: 'success')
      end

      it 'does NOT fire on a health-status update' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .not_to receive(:sync_data_source)
        ds.update_health_status!
      end

      it 'does NOT fire on an effectiveness_score update' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .not_to receive(:sync_data_source)
        ds.recalculate_effectiveness!(freshness: 0.5)
      end

      it 'does NOT fire when an unrelated attribute changes' do
        ds = create(:ai_data_source, account: account)
        expect_any_instance_of(Ai::DataSourceGraph::BridgeService)
          .not_to receive(:sync_data_source)
        ds.update!(priority_order: 42)
      end

      it 'skips the sync entirely for an accountless record' do
        # account_id guard. account_id is NOT NULL at the DB level, so we can't
        # persist an accountless row; instead invoke the private callback
        # directly on an in-memory record to prove the guard short-circuits
        # before the bridge is ever instantiated.
        ds = build(:ai_data_source, account: nil)
        ds.account_id = nil
        expect(Ai::DataSourceGraph::BridgeService).not_to receive(:new)
        ds.send(:sync_to_knowledge_graph)
      end
    end
  end
end
