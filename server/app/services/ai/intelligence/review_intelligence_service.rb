# frozen_string_literal: true

module Ai
  module Intelligence
    class ReviewIntelligenceService
      POSITIVE_WORDS = %w[
        great excellent amazing wonderful fantastic good love best perfect awesome
        helpful reliable fast efficient intuitive easy smooth solid impressive stellar
        outstanding superb brilliant remarkable exceptional wonderful terrific
      ].freeze

      NEGATIVE_WORDS = %w[
        bad terrible awful horrible poor slow buggy broken crash error frustrating
        difficult confusing ugly worst useless unreliable disappointing lacking
        unstable expensive overpriced clunky painful annoying
      ].freeze

      SPAM_PATTERNS = [
        /buy now|click here|free money|act now|limited time/i,
        /(.)\1{5,}/,
        /https?:\/\/[^\s]+\.(xyz|tk|ml|ga|cf)/i
      ].freeze

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Analyze review text for sentiment
      def sentiment_analysis(review_id:)
        review = find_review!(review_id)
        return review unless review.is_a?(MarketplaceReview)

        text = "#{review.title} #{review.content}".downcase
        words = text.scan(/\w+/)

        pos_count = words.count { |w| POSITIVE_WORDS.include?(w) }
        neg_count = words.count { |w| NEGATIVE_WORDS.include?(w) }
        total_sentiment_words = pos_count + neg_count

        score = if total_sentiment_words > 0
                  (pos_count.to_f / total_sentiment_words).round(3)
                else
                  0.5
                end

        # Factor in the star rating
        rating_weight = (review.rating - 3) / 4.0
        adjusted_score = ((score * 0.6) + ((rating_weight + 0.5) * 0.4)).clamp(0, 1).round(3)

        sentiment = if adjusted_score > 0.6 then "positive"
                    elsif adjusted_score < 0.4 then "negative"
                    else "neutral"
                    end

        pos_keywords = words.select { |w| POSITIVE_WORDS.include?(w) }.uniq
        neg_keywords = words.select { |w| NEGATIVE_WORDS.include?(w) }.uniq

        success_response(
          review_id: review.id,
          sentiment: sentiment,
          score: adjusted_score,
          positive_keywords: pos_keywords,
          negative_keywords: neg_keywords,
          rating: review.rating,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("sentiment_analysis", e)
      end

      # Scan recent reviews for spam patterns
      def spam_detection
        reviews = MarketplaceReview.where(account_id: @account.id)
                                   .where("created_at >= ?", 7.days.ago)
                                   .order(created_at: :desc)
                                   .limit(200)

        flagged = reviews.filter_map { |r| detect_spam(r) }

        success_response(
          flagged_reviews: flagged,
          total_scanned: reviews.count,
          spam_rate: reviews.count > 0 ? (flagged.size.to_f / reviews.count * 100).round(1) : 0,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("spam_detection", e)
      end

      # Generate suggested response template based on review sentiment
      def generate_response(review_id:)
        review = find_review!(review_id)
        return review unless review.is_a?(MarketplaceReview)

        sentiment_result = sentiment_analysis(review_id: review_id)
        sentiment = sentiment_result[:sentiment] || "neutral"

        template = build_response_template(review, sentiment)

        success_response(
          review_id: review.id,
          sentiment: sentiment,
          suggested_response: template,
          generated_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("generate_response", e)
      end

      # Aggregate CommunityAgentRating scores per agent, identify quality trends
      def agent_quality_assessment
        ratings = CommunityAgentRating.joins(:community_agent)
                                       .where(community_agents: { owner_account_id: @account.id })
                                       .where("community_agent_ratings.created_at >= ?", 90.days.ago)

        agent_scores = ratings.group(:community_agent_id)
                              .select(
                                "community_agent_id",
                                "AVG(rating) as avg_rating",
                                "COUNT(*) as rating_count",
                                "MIN(rating) as min_rating",
                                "MAX(rating) as max_rating"
                              )

        assessments = agent_scores.map do |score|
          recent = ratings.where(community_agent_id: score.community_agent_id)
                          .where("community_agent_ratings.created_at >= ?", 30.days.ago)
                          .average(:rating)&.to_f || 0
          older = ratings.where(community_agent_id: score.community_agent_id)
                         .where("community_agent_ratings.created_at < ?", 30.days.ago)
                         .average(:rating)&.to_f || 0

          trend = if recent > 0 && older > 0
                    recent > older + 0.3 ? "improving" : recent < older - 0.3 ? "declining" : "stable"
                  else
                    "insufficient_data"
                  end

          {
            community_agent_id: score.community_agent_id,
            avg_rating: score.avg_rating.to_f.round(2),
            rating_count: score.rating_count,
            min_rating: score.min_rating,
            max_rating: score.max_rating,
            recent_avg: recent.round(2),
            trend: trend
          }
        end

        success_response(
          assessments: assessments.sort_by { |a| -a[:avg_rating] },
          total_agents: assessments.size,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("agent_quality_assessment", e)
      end

      private

      def find_review!(id)
        MarketplaceReview.where(account_id: @account.id).find_by(id: id) ||
          error_hash("Review not found: #{id}")
      end

      def detect_spam(review)
        reasons = []
        text = "#{review.title} #{review.content}"

        # Check spam patterns
        SPAM_PATTERNS.each do |pattern|
          reasons << "matches_spam_pattern" if pattern.match?(text)
        end

        # Check for duplicate content
        duplicates = MarketplaceReview.where(account_id: @account.id)
                                      .where.not(id: review.id)
                                      .where(content: review.content)
        reasons << "duplicate_content" if review.content.present? && duplicates.exists?

        # Check for suspicious rating patterns (all 5s or all 1s from same user)
        user_ratings = MarketplaceReview.where(user_id: review.user_id)
                                        .where("created_at >= ?", 7.days.ago)
        if user_ratings.count >= 5
          avg = user_ratings.average(:rating).to_f
          reasons << "suspicious_rating_pattern" if avg >= 4.9 || avg <= 1.1
        end

        # Check high review volume from single user
        recent_count = MarketplaceReview.where(user_id: review.user_id)
                                        .where("created_at >= ?", 24.hours.ago).count
        reasons << "high_volume_reviewer" if recent_count > 10

        return nil if reasons.empty?

        {
          review_id: review.id,
          user_id: review.user_id,
          rating: review.rating,
          reasons: reasons.uniq,
          confidence: [reasons.size * 0.3, 1.0].min.round(2),
          created_at: review.created_at.iso8601
        }
      end

      def build_response_template(review, sentiment)
        case sentiment
        when "positive"
          "Thank you for your wonderful #{review.rating}-star review! " \
            "We're thrilled to hear about your positive experience. " \
            "Your feedback helps us continue improving our services."
        when "negative"
          "Thank you for sharing your feedback. We're sorry to hear about your experience " \
            "and take your concerns seriously. We'd like to learn more about what happened " \
            "and work towards a resolution. Please reach out to our support team so we can help."
        else
          "Thank you for taking the time to share your thoughts. " \
            "We appreciate your honest feedback and will use it to improve our services. " \
            "If there's anything specific we can do better, please don't hesitate to let us know."
        end
      end

      def success_response(**data) = { success: true }.merge(data)

      def error_hash(message) = { success: false, error: message }

      def error_response(method_name, exception)
        @logger.error("[Ai::Intelligence::ReviewIntelligenceService##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end
    end
  end
end
