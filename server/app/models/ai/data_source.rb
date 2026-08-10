# frozen_string_literal: true

module Ai
  class DataSource < ApplicationRecord
    self.table_name = "ai_data_sources"

    # Concerns
    include Auditable

    # Associations
    belongs_to :account
    has_many :credentials, class_name: "Ai::DataSourceCredential",
             foreign_key: "ai_data_source_id", dependent: :destroy
    has_many :endpoints, class_name: "Ai::DataSourceEndpoint",
             foreign_key: "ai_data_source_id", dependent: :destroy
    has_many :queries, class_name: "Ai::DataSourceQuery",
             foreign_key: "ai_data_source_id", dependent: :destroy
    has_many :subscriptions, class_name: "Ai::DataSourceSubscription",
             foreign_key: "ai_data_source_id", dependent: :destroy
    has_many :config_versions, class_name: "Ai::DataSourceConfigVersion",
             foreign_key: "ai_data_source_id", dependent: :destroy
    has_many :published_posts, class_name: "Ai::PublishedPost",
             foreign_key: "ai_data_source_id", dependent: :destroy
    has_many :content_drafts, class_name: "Ai::ContentDraft",
             foreign_key: "ai_data_source_id", dependent: :destroy
    # DELIBERATELY UNSCOPED, unlike Ai::Skill's (IMP-8eb424f427bc). The offer
    # called these two "the same unscoped shape, fix both or neither", but they
    # are not equivalent: index_ai_kg_nodes_on_ai_data_source_id is a plain
    # partial index, NOT unique, so several ACTIVE nodes may already share this
    # FK — an active-scope would not make this association deterministic, and
    # would make things worse. DataSourceGraph::BridgeService#sync_data_source
    # currently finds an archived node and revives it (self-healing); scoped, it
    # would take the create branch and add a duplicate that no index prevents.
    # There is also no before_destroy archive hook here (Ai::Skill has one), so a
    # scoped dependent: :nullify would leave a dangling ai_data_source_id on any
    # non-active node, unenforced by any FK constraint. Tracked separately.
    has_one :knowledge_graph_node, class_name: "Ai::KnowledgeGraphNode",
            foreign_key: "ai_data_source_id", dependent: :nullify

    # Constants
    # source_type is now a free-form, generic label — NOT an enforced enum. This
    # list is UI guidance only (preset/autocomplete hints), so a brand-new source
    # type can be created without a code change. Keep SOURCE_TYPES as a backward-
    # compatible alias so existing references (presets, tests, callers) keep working.
    SUGGESTED_SOURCE_TYPES = %w[noaa_ncei noaa_gfs noaa_observations open_meteo fred yahoo_finance espn newsapi custom].freeze
    SOURCE_TYPES = SUGGESTED_SOURCE_TYPES
    HEALTH_STATUSES = %w[healthy degraded critical unknown].freeze

    # Validations
    validates :name, presence: true, length: { maximum: 255 },
              uniqueness: { scope: :account_id, case_sensitive: false }
    validates :slug, presence: true, length: { maximum: 100 },
              uniqueness: { scope: :account_id },
              format: { with: /\A[a-z0-9_-]+\z/, message: "must be lowercase alphanumeric with hyphens/underscores" }
    # source_type is generic: any lowercase token is accepted (no inclusion in
    # SUGGESTED_SOURCE_TYPES). Presence + a lowercase format check keep tokens
    # normalized for the by_type scope / KG sync without constraining the set.
    validates :source_type, presence: true, length: { maximum: 50 },
              format: { with: /\A[a-z0-9_-]+\z/, message: "must be lowercase alphanumeric with hyphens/underscores" }
    validates :category, length: { maximum: 100 }, allow_nil: true
    validates :priority_order, numericality: { greater_than: 0 }
    validates :health_status, inclusion: { in: HEALTH_STATUSES }, allow_nil: true

    # Free-form grouping for the generic source model (e.g. "weather",
    # "finance"). Nullable — declared explicitly so the by_category scope and
    # form binding see a typed attribute.
    attribute :category, :string

    # JSON column defaults (lambda required for mutable defaults)
    attribute :capabilities, :json, default: -> { [] }
    attribute :configuration, :json, default: -> { {} }
    attribute :rate_limits, :json, default: -> { {} }
    attribute :default_parameters, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }
    attribute :auth_config, :json, default: -> { {} }

    # Callbacks
    before_validation :generate_slug, on: :create
    after_commit :sync_to_knowledge_graph, on: [:create, :update]

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :by_type, ->(type) { where(source_type: type) }
    scope :by_category, ->(category) { where(category: category) }
    scope :for_account, ->(account) { where(account: account) }
    scope :ordered_by_priority, -> { order(:priority_order, :name) }
    scope :requiring_auth, -> { where(requires_auth: true) }

    def to_param
      slug
    end

    # Returns the best available credential for making API requests.
    def active_credential
      credentials.where(is_active: true, is_default: true).first ||
        credentials.where(is_active: true).order(created_at: :desc).first
    end

    # Convenience accessor for the active credential's API key.
    def api_key
      active_credential&.decrypted_api_key
    end

    def healthy?
      is_active? && %w[healthy unknown].include?(health_status)
    end

    # Check if a request is within configured rate limits.
    # Returns { allowed: true } or { allowed: false, retry_after: seconds, limit: "limit_name" }.
    def check_quota!
      limits = rate_limits
      return { allowed: true } if limits.blank?

      now = Time.current
      usage = current_quota_usage

      if limits["requests_per_minute"] && usage[:minute] >= limits["requests_per_minute"]
        return { allowed: false, retry_after: 60 - now.sec, limit: "requests_per_minute" }
      end
      if limits["requests_per_hour"] && usage[:hour] >= limits["requests_per_hour"]
        return { allowed: false, retry_after: 3600 - (now.min * 60 + now.sec), limit: "requests_per_hour" }
      end
      if limits["requests_per_day"] && usage[:day] >= limits["requests_per_day"]
        return { allowed: false, retry_after: 86_400 - (now.hour * 3600 + now.min * 60 + now.sec), limit: "requests_per_day" }
      end

      { allowed: true }
    end

    # Record a completed request for quota tracking. Uses Redis atomic counters.
    def record_request!(bytes: 0)
      prefix = "data_source:#{id}:quota"
      begin
        redis = Powernode::Redis.client
      rescue StandardError
        return
      end

      now = Time.current
      minute_key = "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}"
      hour_key = "#{prefix}:hr:#{now.strftime('%Y%m%d%H')}"
      day_key = "#{prefix}:day:#{now.strftime('%Y%m%d')}"

      redis.multi do |tx|
        tx.incr(minute_key)
        tx.expire(minute_key, 120)
        tx.incr(hour_key)
        tx.expire(hour_key, 7200)
        tx.incr(day_key)
        tx.expire(day_key, 172_800)
      end

      if bytes > 0
        bw_key = "#{prefix}:bw:#{now.strftime('%Y%m%d')}"
        redis.incrby(bw_key, bytes)
        redis.expire(bw_key, 172_800)
      end
    end

    # Current quota usage from Redis counters.
    def current_quota_usage
      prefix = "data_source:#{id}:quota"
      begin
        redis = Powernode::Redis.client
      rescue StandardError
        return { minute: 0, hour: 0, day: 0, bandwidth_today: 0 }
      end

      now = Time.current
      minute_key = "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}"
      hour_key = "#{prefix}:hr:#{now.strftime('%Y%m%d%H')}"
      day_key = "#{prefix}:day:#{now.strftime('%Y%m%d')}"
      bw_key = "#{prefix}:bw:#{now.strftime('%Y%m%d')}"

      values = redis.mget(minute_key, hour_key, day_key, bw_key)
      {
        minute: values[0].to_i,
        hour: values[1].to_i,
        day: values[2].to_i,
        bandwidth_today: values[3].to_i
      }
    end

    # Returns a summary of current usage vs configured limits with utilization percentages.
    def quota_summary
      usage = current_quota_usage
      limits = rate_limits
      {
        usage: usage,
        limits: limits,
        utilization: {
          minute_pct: limits["requests_per_minute"] ? (usage[:minute].to_f / limits["requests_per_minute"] * 100).round(1) : nil,
          hour_pct: limits["requests_per_hour"] ? (usage[:hour].to_f / limits["requests_per_hour"] * 100).round(1) : nil,
          day_pct: limits["requests_per_day"] ? (usage[:day].to_f / limits["requests_per_day"] * 100).round(1) : nil
        }
      }
    end

    # Recalculates health status based on active credential state.
    def update_health_status!
      cred = active_credential
      status = if !is_active?
                 "unknown"
               elsif cred.nil?
                 "unknown"
               elsif cred.consecutive_failures >= 5
                 "critical"
               elsif cred.consecutive_failures >= 2
                 "degraded"
               else
                 "healthy"
               end
      update_columns(health_status: status, last_health_check_at: Time.current)
    end

    # Records the outcome of a single query against this source. The
    # ai_data_source_queries table IS the per-request audit log (written
    # by Ai::DataSources::QueryService) — this method only maintains the
    # rolled-up scoring counters used by recalculate_effectiveness!, so it
    # does NOT create a separate usage record.
    #
    #   outcome:  "success" or "failure"
    #   freshness: optional 0.0..1.0 override for the freshness signal on
    #              this query (e.g. how recent the upstream data was). When
    #              nil, recalculate_effectiveness! derives freshness from
    #              health-check / last-used recency instead.
    #   agent:    optional requesting agent (reserved for future per-agent
    #             attribution; counters are source-wide today).
    def record_query!(outcome:, freshness: nil, agent: nil)
      pos = positive_usage_count + (outcome == "success" ? 1 : 0)
      neg = negative_usage_count + (outcome == "success" ? 0 : 1)

      # ONE write that bypasses callbacks/audit. Counter bumps on the hot fetch
      # path must not flood the audit hash chain (Auditable#after_update) nor
      # trigger an after_commit KG re-sync (the embedding only depends on
      # name/description/source_type, not on usage counters).
      update_columns(
        usage_count: usage_count + 1,
        positive_usage_count: pos,
        negative_usage_count: neg,
        last_used_at: Time.current
      )

      total = pos + neg
      recalculate_effectiveness!(freshness: freshness) if total.positive? && (total % 5).zero?
    end

    # Blends three trust signals into a single 0..1 effectiveness score:
    #   - knowledge-graph node confidence (semantic standing in the graph)
    #   - observed query success rate
    #   - freshness (how recently the source produced usable data)
    def recalculate_effectiveness!(freshness: nil)
      kg_confidence = knowledge_graph_node&.confidence&.to_f || 0.5
      usage_rate = usage_success_rate
      fresh = freshness.nil? ? freshness_score : freshness.to_f.clamp(0.0, 1.0)

      score = (0.3 * kg_confidence + 0.4 * usage_rate + 0.3 * fresh).round(4)
      # update_columns (not update!) so the periodic recalc also stays off the
      # audit + KG-resync callback path — same hot-path rationale as record_query!.
      update_columns(effectiveness_score: score)
    end

    # Share of recorded queries that succeeded. Neutral 0.5 until there is
    # at least one outcome to avoid penalizing brand-new sources.
    def usage_success_rate
      total = positive_usage_count + negative_usage_count
      return 0.5 if total.zero?

      (positive_usage_count.to_f / total).round(4)
    end

    # Capture a CREDENTIAL-FREE config snapshot of this source (+ its endpoints)
    # as the next Ai::DataSourceConfigVersion, delegating to
    # Ai::DataSources::ConfigPortabilityService. This is the LIGHTWEIGHT, OPT-IN
    # hook for config versioning: callers (controller update paths, the MCP
    # action, a future "snapshot before change" flow) invoke it explicitly.
    #
    # We deliberately do NOT register an after_update_commit callback to snapshot
    # automatically — that would be too implicit and would risk snapshot storms
    # (every counter/health/effectiveness update_columns bump, KG re-sync, etc.
    # could trip it). Keeping the snapshot an explicit call leaves the decision of
    # WHEN a version is worth capturing with the caller.
    #
    # @param note [String, nil] optional human note recorded on the version.
    # @param created_by_type [String] provenance — one of
    #   Ai::DataSourceConfigVersion::CREATED_BY_TYPES (default "manual").
    # @return [Ai::DataSourceConfigVersion] the persisted version record.
    def snapshot_config!(note: nil, created_by_type: "manual")
      Ai::DataSources::ConfigPortabilityService
        .new(account: account)
        .snapshot!(self, created_by_type: created_by_type, note: note)
    end

    private

    # Mirrors Ai::Skill#sync_to_knowledge_graph: on every create/update,
    # (re)build this source's knowledge-graph node + embedding via the
    # DataSourceGraph bridge. Guarded so accountless rows are skipped and
    # so environments without an embedding backend (test/CI) degrade to a
    # logged warning instead of raising out of the commit.
    def sync_to_knowledge_graph
      return unless account_id.present?
      # Only (re)build the embedding/node when a field that actually feeds the
      # embedding text changed (name/description/source_type/slug). Counter,
      # health, and effectiveness updates must NOT trigger a re-embed. On create
      # every saved_change_to_* is true, so the initial node is always built.
      return unless saved_change_to_name? || saved_change_to_description? ||
                    saved_change_to_source_type? || saved_change_to_slug?

      Ai::DataSourceGraph::BridgeService.new(Account.find(account_id)).sync_data_source(self)
    rescue StandardError => e
      Rails.logger.warn "[Ai::DataSource] KG sync failed for data source #{id}: #{e.message}"
    end

    # Recency-derived freshness in 0..1, defaulting to 0.5 when the source
    # has never been used or health-checked. Uses the most recent of
    # last_used_at / last_health_check_at and decays linearly over a 7-day
    # window: just-touched -> ~1.0, a week stale -> 0.0.
    def freshness_score
      reference = [last_used_at, last_health_check_at].compact.max
      return 0.5 if reference.nil?

      age_days = (Time.current - reference) / 1.day
      return 1.0 if age_days <= 0

      (1.0 - (age_days / 7.0)).clamp(0.0, 1.0).round(4)
    end

    def generate_slug
      return if slug.present?

      base = name.to_s.parameterize.underscore.first(90)
      self.slug = base
      counter = 1
      while self.class.where(account_id: account_id, slug: slug).where.not(id: id).exists?
        self.slug = "#{base}_#{counter}"
        counter += 1
      end
    end
  end
end
