# frozen_string_literal: true

module Ai
  module CodeFactory
    class ThreadResolverService
      class ResolverError < StandardError; end

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Resolve bot-authored unresolved comment threads
      # NEVER resolves threads with human participation
      def resolve_bot_threads(review_state:)
        bot_comments = find_bot_only_unresolved_comments(review_state)

        resolved_count = 0
        bot_comments.each do |comment|
          resolve_comment(comment)
          resolved_count += 1
        end

        review_state.update!(bot_threads_resolved: review_state.bot_threads_resolved + resolved_count)

        @logger.info("[CodeFactory::ThreadResolver] Resolved #{resolved_count} bot-only threads for PR ##{review_state.pr_number}")
        { resolved_count: resolved_count }
      rescue StandardError => e
        @logger.error("[CodeFactory::ThreadResolver] Error: #{e.message}")
        raise ResolverError, e.message
      end

      private

      def find_bot_only_unresolved_comments(review_state)
        Ai::CodeReviewComment.where(
          account: @account,
          pr_number: review_state.pr_number,
          resolved: false,
          author_type: "bot"
        ).where.not(
          id: Ai::CodeReviewComment.where(
            account: @account,
            pr_number: review_state.pr_number
          ).where(author_type: "human").select(:thread_id)
           .where.not(thread_id: nil)
           .then { |human_threads|
             Ai::CodeReviewComment.where(thread_id: human_threads).select(:id)
           }
        )
      rescue StandardError
        # Fallback: if the query structure doesn't match, return empty
        Ai::CodeReviewComment.none
      end

      def resolve_comment(comment)
        comment.update!(resolved: true, resolved_at: Time.current)
      rescue StandardError => e
        @logger.warn("[CodeFactory::ThreadResolver] Could not resolve comment #{comment.id}: #{e.message}")
      end
    end
  end
end
