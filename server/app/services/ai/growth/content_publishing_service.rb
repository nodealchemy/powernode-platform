# frozen_string_literal: true

module Ai
  module Growth
    class ContentPublishingError < StandardError; end

    # Draft -> publish (D2): dispatches a reviewable Ai::ContentDraft (D1) to
    # its target data source(s) through the SAME approval-gated write path
    # every other governed write already uses. This service never posts
    # directly — every dispatch is handed to Ai::Growth::CrossPostService
    # (G2), which itself dispatches through Ai::Tools::DataSourceTool
    # #guarded_fetch, so an agent lacking ai.data_sources.manage gets a
    # per-target Ai::AgentProposal instead of a live post. A successful
    # dispatch against an endpoint opted into
    # metadata["captures_published_post"] (e.g. x-com's "Create post") is
    # AUTOMATICALLY recorded as an Ai::PublishedPost by
    # Ai::Growth::PublishedPostRecorder — already wired into guarded_fetch,
    # so this service does not record provenance itself; it only reacts to
    # whether the underlying dispatch actually went live.
    #
    # THREAD HANDLING: a draft split into segments (see ContentDraft#thread?)
    # is published as an ORDERED SEQUENCE of independent posts — segment i+1
    # is dispatched only after segment i completes, to every target. TRUE
    # reply-chaining (linking segment i+1 to segment i's external post id) is
    # PARKED: no current provider endpoint template (see
    # Ai::DataSources::TemplateLibrary) exposes a reply-to body param —
    # x-com's "Create post" body_template is {"text" => "{text}"} only, with
    # nothing to address a prior post by. Adding it later is a metadata
    # opt-in on the endpoint (mirrors captures_published_post/side_effecting/
    # max_content_length), not a change to this service.
    #
    # MULTI-PROVIDER: the draft's own target (Ai::ContentDraft#data_source) is
    # always included; additional_targets fans the SAME content/segments out
    # to more providers in the SAME pass by handing every segment's full
    # target list (primary + additional) to CrossPostService in one call —
    # there is no separate fan-out path duplicating what CrossPostService
    # already does.
    class ContentPublishingService
      # A draft in either of these statuses can never be (re-)published:
      # "published" already went live, "rejected" was explicitly declined.
      TERMINAL_STATUSES = %w[published rejected].freeze

      def initialize(account:, agent: nil, user: nil)
        @account = account
        @agent = agent
        @user = user
        @cross_post_service = Ai::Growth::CrossPostService.new(account: account, agent: agent, user: user)
      end

      # @param draft [Ai::ContentDraft] must belong to this service's account
      # @param additional_targets [Array<Hash>] extra { data_source_id:, params: {} }
      #   targets to cross-post the SAME content to, beyond the draft's own
      #   data source (see class comment "MULTI-PROVIDER").
      # @return [Hash] aggregate outcome (target/published/proposed/failed
      #   counts, per-segment CrossPostService results, and the draft's
      #   resulting status)
      def publish(draft:, additional_targets: [])
        raise ContentPublishingError, "draft is required" unless draft.is_a?(Ai::ContentDraft)
        raise ContentPublishingError, "draft #{draft.id} belongs to a different account" unless draft.account_id == @account.id
        if TERMINAL_STATUSES.include?(draft.status)
          raise ContentPublishingError, "draft #{draft.id} is '#{draft.status}' and cannot be published"
        end

        targets = build_targets(draft, additional_targets)
        segments = draft.segments.presence || [ draft.content ]

        # Sequential, not parallel: see "THREAD HANDLING" above — segment i+1
        # is only attempted once segment i's dispatch (to every target) is
        # complete. A single-segment (non-thread) draft is just one pass.
        dispatched = segments.map { |segment| @cross_post_service.publish(content: segment, targets: targets) }

        apply_outcome(draft, dispatched)
      end

      private

      # Primary target is always the draft's own data source; additional
      # targets extend (never replace) it. De-duplicated on the RESOLVED
      # data source id (not the raw identifier) so an additional target that
      # repeats the primary by SLUG rather than the draft's own UUID FK is
      # still recognized as a no-op, not a double-post.
      def build_targets(draft, additional_targets)
        primary = { "data_source_id" => draft.ai_data_source_id }
        extra = Array(additional_targets).filter_map do |target|
          hash = target.respond_to?(:to_h) ? target.to_h.stringify_keys : nil
          next if hash.blank? || hash["data_source_id"].blank?

          hash
        end

        [ primary, *extra ].uniq { |target| resolve_data_source_id(target["data_source_id"]) }
      end

      # Resolve a slug-or-id identifier to its canonical data source UUID for
      # dedup purposes; falls back to the raw identifier when it does not
      # resolve (CrossPostService will surface the "not found" failure).
      def resolve_data_source_id(identifier)
        ds = Ai::DataSource.for_account(@account).find_by(slug: identifier) ||
             Ai::DataSource.for_account(@account).find_by(id: identifier)
        ds&.id || identifier
      end

      # Advances the draft's status ONLY on a real outcome:
      # - every target, every segment actually published -> "published"
      # - anything filed a proposal (agent lacking ai.data_sources.manage)
      #   and the draft hadn't been reviewed yet -> "pending_review" (a
      #   human now has something to approve); a draft already past "draft"
      #   (e.g. "approved") is left alone rather than regressed.
      # - outright failures with no proposals leave status untouched so the
      #   caller can inspect failed_count and retry — CrossPostService's own
      #   philosophy (never abort/hide a partial batch) applies here too.
      def apply_outcome(draft, dispatched)
        target_count = dispatched.sum { |d| d[:target_count] }
        published_count = dispatched.sum { |d| d[:published_count] }
        proposed_count = dispatched.sum { |d| d[:proposed_count] }
        failed_count = dispatched.sum { |d| d[:failed_count] }
        fully_published = target_count.positive? && published_count == target_count

        if fully_published
          draft.update!(status: "published", metadata: draft.metadata.merge(
            "published_at" => Time.current.utc.iso8601,
            "publish_target_count" => target_count
          ))
        elsif proposed_count.positive? && draft.status == "draft"
          draft.update!(status: "pending_review")
        end

        {
          draft_id: draft.id,
          status: draft.status,
          thread: draft.thread?,
          segment_count: dispatched.size,
          target_count: target_count,
          published_count: published_count,
          proposed_count: proposed_count,
          failed_count: failed_count,
          fully_published: fully_published,
          segments: dispatched
        }
      end
    end
  end
end
