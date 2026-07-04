# frozen_string_literal: true

module Ai
  module Growth
    # Cross-posting orchestration (G2): fans ONE piece of content out to N
    # connected providers' publish endpoints through the SAME approval-gated
    # write path every other data-source write already goes through —
    # Ai::Tools::DataSourceTool (#guarded_fetch / #propose_write). There is no
    # side-channel dispatch: each target is published (or proposed) by handing
    # action "data_source_query" to the tool exactly as a single-provider
    # publish would, so an agent lacking ai.data_sources.manage gets a
    # requires_approval proposal PER TARGET instead of a silent post — never a
    # live write it was not authorized for.
    #
    # Publish-endpoint discovery is metadata-driven (mirrors
    # EngagementIngestionService's engagement_metrics flag and
    # DataSourceTool#write_endpoint?'s own gate): a target's SIDE-EFFECTING
    # endpoint (metadata["side_effecting"] == true) is used, so a new provider
    # template only needs that flag on its own create-post-shaped endpoint —
    # zero code change here.
    class CrossPostService
      SETTINGS_KEY = "growth_analytics"
      DEFAULT_MAX_TARGETS = 10

      def initialize(account:, agent: nil, user: nil)
        @account = account
        @agent = agent
        @user = user
        @tool = Ai::Tools::DataSourceTool.new(account: account, agent: agent, user: user)
      end

      # @param content [String] text published verbatim to every target, as
      #   the endpoint's "text" body param.
      # @param targets [Array<Hash>] { data_source_id:, params: {} } — a
      #   target's own params OVERRIDE/EXTEND the shared text, for whatever
      #   else its endpoint's body_template needs (Reddit's sr/title,
      #   LinkedIn's person_id, Bluesky's repo/created_at, ...) — this
      #   service never hardcodes a provider's auth-specific shape.
      # @return [Hash] per-target results plus a summary tally
      def publish(content:, targets:)
        raise ArgumentError, "content is required" if content.blank?

        targets = Array(targets)
        raise ArgumentError, "targets is required" if targets.empty?
        raise ArgumentError, "too many targets (max #{max_targets})" if targets.size > max_targets

        results = targets.map { |target| publish_one(content, target) }

        {
          content: content,
          target_count: results.size,
          published_count: results.count { |r| r[:published] },
          proposed_count: results.count { |r| r[:requires_approval] },
          failed_count: results.count { |r| !r[:published] && !r[:requires_approval] },
          results: results
        }
      end

      private

      def publish_one(content, target)
        target = target.respond_to?(:to_h) ? target.to_h.stringify_keys : {}
        data_source_id = target["data_source_id"]
        return failure(data_source_id, "data_source_id is required") if data_source_id.blank?

        ds = resolve_source(data_source_id)
        return failure(data_source_id, "data source not found") unless ds

        endpoint = publish_endpoint(ds)
        return failure(data_source_id, "no publish (side-effecting) endpoint configured") unless endpoint

        overrides = (target["params"] || {}).to_h
        params = { "text" => content }.merge(overrides)

        envelope = @tool.execute(params: {
          action: "data_source_query",
          data_source_id: ds.id,
          endpoint_id: endpoint.id,
          params: params
        })

        summarize(ds, endpoint, envelope)
      end

      def resolve_source(identifier)
        Ai::DataSource.for_account(@account).find_by(slug: identifier) ||
          Ai::DataSource.for_account(@account).find_by(id: identifier)
      end

      # The account-scoped source's SIDE-EFFECTING endpoint — the same
      # metadata flag DataSourceTool#write_endpoint? and every provider
      # template's own "Create post"/"Submit post"/"Create status" endpoint
      # already carries. Picks the first if a source somehow has more than
      # one (none currently do).
      def publish_endpoint(ds)
        ds.endpoints.detect { |endpoint| side_effecting?(endpoint) }
      end

      def side_effecting?(endpoint)
        meta = endpoint.metadata.is_a?(Hash) ? endpoint.metadata.stringify_keys : {}
        ActiveModel::Type::Boolean.new.cast(meta["side_effecting"])
      end

      def summarize(ds, endpoint, envelope)
        {
          data_source_id: ds.id,
          data_source_slug: ds.slug,
          endpoint_id: endpoint.id,
          endpoint_slug: endpoint.slug,
          published: envelope[:success] == true && envelope[:requires_approval] != true,
          requires_approval: envelope[:requires_approval] == true,
          proposal_id: envelope[:proposal_id],
          status: envelope[:status],
          error: envelope[:error]
        }
      end

      def failure(data_source_id, message)
        { data_source_id: data_source_id, published: false, requires_approval: false, error: message }
      end

      def max_targets
        configured = @account&.settings&.dig(SETTINGS_KEY, "cross_post_max_targets")
        configured.present? ? configured.to_i : DEFAULT_MAX_TARGETS
      end
    end
  end
end
