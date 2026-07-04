# frozen_string_literal: true

# Growth Analytics Controller (G2) - Audience Insights, Posting-Time
# Optimization & Cross-Post Orchestration
#
# There is no pre-existing "connected social provider" observability home —
# Ai::RoiMetric/RoiCalculationsController track AI-operation cost/value and
# AnalyticsController tracks AI-ops cost/performance/usage, neither of which
# covers social-provider audience engagement (Ai::PublishedPost /
# Ai::PostEngagementSnapshot, G1). This is the minimal read (+ one governed
# write) surface for that data, following the SAME
# service-backed/render_success/permission-gated shape as
# RoiCalculationsController/AnalyticsController rather than a new dashboard.
module Api
  module V1
    module Ai
      class GrowthAnalyticsController < ApplicationController
        include AuditLogging

        before_action :validate_permissions

        # GET /api/v1/ai/growth/audience_insights
        def audience_insights
          service = ::Ai::Growth::AudienceInsightsService.new(account: current_account, time_range: time_range)

          render_success({
            insights: service.summary,
            time_range: time_range_info,
            generated_at: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/growth/posting_time_recommendations
        def posting_time_recommendations
          service = ::Ai::Growth::PostingTimeOptimizer.new(account: current_account, time_range: time_range)

          render_success({
            recommendations: service.recommendations,
            time_range: time_range_info,
            generated_at: Time.current.iso8601
          })
        end

        # POST /api/v1/ai/growth/cross_post
        # body: { content: "...", targets: [{ data_source_id:, params: {} }, ...] }
        #
        # This REST action is a DIRECT human write, exactly like
        # DataSourcesController's own create/update/destroy actions — hard
        # permission-gated, no propose-instead-of-deny fallback (that
        # softening is an AGENT concern only). Ai::Growth::CrossPostService
        # still always dispatches THROUGH Ai::Tools::DataSourceTool's
        # guarded_fetch, so an agent-context caller (e.g. a future MCP tool
        # wrapping this same service, mirroring DataSourceTool's own REST/MCP
        # parity) gets the per-target propose_write fallback instead of a
        # silent write it lacks ai.data_sources.manage for.
        def cross_post
          service = ::Ai::Growth::CrossPostService.new(account: current_account, agent: current_agent, user: current_user)
          result = service.publish(content: params[:content], targets: params[:targets] || [])

          render_success(result)

          log_audit_event("ai.growth.cross_post", current_account,
            metadata: { target_count: result[:target_count], published_count: result[:published_count],
                        proposed_count: result[:proposed_count] }) if current_user
        rescue ArgumentError => e
          render_error(e.message, status: :bad_request)
        end

        private

        def validate_permissions
          return if current_worker

          case action_name
          when "audience_insights", "posting_time_recommendations"
            require_permission("ai.analytics.read")
          when "cross_post"
            # A live write dispatch (fans out to N write endpoints) — same
            # bar as DataSourcesController's own mutation actions, not the
            # lighter .query grant.
            require_permission("ai.data_sources.manage")
          end
        end

        def current_account
          current_user&.account || current_worker&.account
        end

        def current_agent
          nil
        end

        def time_range
          case params[:time_range]
          when "1h" then 1.hour
          when "24h", "1d" then 1.day
          when "7d", "1w" then 1.week
          when "30d", "1m" then 30.days
          when "90d", "3m" then 90.days
          when "1y" then 1.year
          else 30.days
          end
        end

        def time_range_info
          {
            start: time_range.ago.iso8601,
            end: Time.current.iso8601,
            period: params[:time_range] || "30d",
            seconds: time_range.to_i
          }
        end
      end
    end
  end
end
