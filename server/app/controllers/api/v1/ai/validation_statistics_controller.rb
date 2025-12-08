# frozen_string_literal: true

module Api
  module V1
    module Ai
      # ValidationStatisticsController
      #
      # Provides aggregate validation statistics and analytics across workflows.
      # Supports platform-wide and account-scoped statistics.
      #
      class ValidationStatisticsController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission

        # GET /api/v1/ai/validation_statistics
        def show
          time_range = parse_time_range(params[:time_range])

          # Get all workflows for the account
          workflows = current_user.account.ai_workflows

          # Get validations within time range
          validations = WorkflowValidation
                          .joins(:workflow)
                          .where(workflows: { account_id: current_user.account_id })
                          .where('workflow_validations.created_at >= ?', time_range)

          statistics = {
            overview: calculate_overview_stats(workflows, validations),
            health_distribution: calculate_health_distribution(validations),
            status_distribution: calculate_status_distribution(validations),
            issue_categories: calculate_issue_categories(validations),
            trends: calculate_trends(validations),
            top_issues: calculate_top_issues(validations)
          }

          render_success({
            statistics: statistics,
            time_range: {
              start: time_range.iso8601,
              end: Time.current.iso8601,
              period: params[:time_range] || '30d'
            }
          })

          log_audit_event('ai.validation_statistics.read', current_user.account)
        rescue => e
          Rails.logger.error "Failed to get validation statistics: #{e.message}"
          render_error('Failed to get validation statistics', status: :internal_server_error)
        end

        # GET /api/v1/ai/validation_statistics/common_issues
        def common_issues
          time_range = parse_time_range(params[:time_range])
          limit = [params[:limit]&.to_i || 10, 50].min

          validations = WorkflowValidation
                          .joins(:workflow)
                          .where(workflows: { account_id: current_user.account_id })
                          .where('workflow_validations.created_at >= ?', time_range)

          # Aggregate issues by code
          issue_counts = Hash.new(0)
          issue_details = {}

          validations.each do |validation|
            next unless validation.issues.is_a?(Array)

            validation.issues.each do |issue|
              code = issue['code']
              issue_counts[code] += 1

              # Store first occurrence details
              unless issue_details[code]
                issue_details[code] = {
                  code: code,
                  severity: issue['severity'],
                  category: issue['category'],
                  message: issue['message'],
                  auto_fixable: issue['auto_fixable'] || false
                }
              end
            end
          end

          # Sort by count and take top N
          top_issues = issue_counts.sort_by { |_code, count| -count }.first(limit).map do |code, count|
            issue_details[code].merge(count: count)
          end

          render_success({
            common_issues: top_issues,
            total_unique_issues: issue_counts.size,
            time_range: {
              start: time_range.iso8601,
              end: Time.current.iso8601,
              period: params[:time_range] || '30d'
            }
          })

          log_audit_event('ai.validation_statistics.common_issues', current_user.account)
        rescue => e
          Rails.logger.error "Failed to get common issues: #{e.message}"
          render_error('Failed to get common issues', status: :internal_server_error)
        end

        # GET /api/v1/ai/validation_statistics/health_distribution
        def health_distribution
          time_range = parse_time_range(params[:time_range])

          validations = WorkflowValidation
                          .joins(:workflow)
                          .where(workflows: { account_id: current_user.account_id })
                          .where('workflow_validations.created_at >= ?', time_range)

          # Get latest validation for each workflow
          latest_validations = validations
                                .select('DISTINCT ON (workflow_id) *')
                                .order('workflow_id, created_at DESC')

          # Calculate distribution buckets
          distribution = {
            excellent: latest_validations.where('health_score >= ?', 90).count,
            good: latest_validations.where('health_score >= ? AND health_score < ?', 70, 90).count,
            fair: latest_validations.where('health_score >= ? AND health_score < ?', 50, 70).count,
            poor: latest_validations.where('health_score < ?', 50).count
          }

          # Calculate average by bucket
          averages = {
            excellent: latest_validations.where('health_score >= ?', 90).average(:health_score)&.round(1) || 0,
            good: latest_validations.where('health_score >= ? AND health_score < ?', 70, 90).average(:health_score)&.round(1) || 0,
            fair: latest_validations.where('health_score >= ? AND health_score < ?', 50, 70).average(:health_score)&.round(1) || 0,
            poor: latest_validations.where('health_score < ?', 50).average(:health_score)&.round(1) || 0
          }

          render_success({
            distribution: distribution,
            averages: averages,
            total_workflows: latest_validations.count,
            overall_average: latest_validations.average(:health_score)&.round(1) || 0,
            time_range: {
              start: time_range.iso8601,
              end: Time.current.iso8601,
              period: params[:time_range] || '30d'
            }
          })

          log_audit_event('ai.validation_statistics.health_distribution', current_user.account)
        rescue => e
          Rails.logger.error "Failed to get health distribution: #{e.message}"
          render_error('Failed to get health distribution', status: :internal_server_error)
        end

        private

        def require_read_permission
          unless current_user.has_permission?('ai.workflows.read')
            render_error('Insufficient permissions to view validation statistics', status: :forbidden)
          end
        end

        def parse_time_range(range_param)
          case range_param
          when '7d'
            7.days.ago
          when '30d', nil
            30.days.ago
          when '90d'
            90.days.ago
          when '1y'
            1.year.ago
          else
            30.days.ago
          end
        end

        def calculate_overview_stats(workflows, validations)
          total_workflows = workflows.count
          validated_workflows = workflows.joins(:workflow_validations).distinct.count

          latest_validations = validations
                                .select('DISTINCT ON (workflow_id) *')
                                .order('workflow_id, created_at DESC')

          {
            total_workflows: total_workflows,
            validated_workflows: validated_workflows,
            unvalidated_workflows: total_workflows - validated_workflows,
            average_health_score: latest_validations.average(:health_score)&.round(1) || 0,
            valid_count: latest_validations.valid.count,
            invalid_count: latest_validations.invalid.count,
            warning_count: latest_validations.warnings.count,
            total_validations: validations.count,
            validations_last_24h: validations.where('created_at >= ?', 24.hours.ago).count
          }
        end

        def calculate_health_distribution(validations)
          latest_validations = validations
                                .select('DISTINCT ON (workflow_id) *')
                                .order('workflow_id, created_at DESC')

          {
            healthy: latest_validations.healthy.count,
            unhealthy: latest_validations.unhealthy.count,
            moderate: latest_validations.where('health_score >= ? AND health_score < ?', 60, 80).count
          }
        end

        def calculate_status_distribution(validations)
          latest_validations = validations
                                .select('DISTINCT ON (workflow_id) *')
                                .order('workflow_id, created_at DESC')

          {
            valid: latest_validations.valid.count,
            invalid: latest_validations.invalid.count,
            warning: latest_validations.warnings.count
          }
        end

        def calculate_issue_categories(validations)
          category_counts = Hash.new(0)

          validations.each do |validation|
            next unless validation.issues.is_a?(Array)

            validation.issues.each do |issue|
              category_counts[issue['category']] += 1 if issue['category']
            end
          end

          category_counts
        end

        def calculate_trends(validations)
          # Group by day and calculate average health score
          daily_stats = validations
                          .group("DATE(created_at)")
                          .select("DATE(created_at) as date,
                                   AVG(health_score) as avg_score,
                                   COUNT(*) as validation_count")
                          .order("date DESC")
                          .limit(30)

          daily_stats.map do |stat|
            {
              date: stat.date.iso8601,
              avg_health_score: stat.avg_score&.round(1) || 0,
              validation_count: stat.validation_count
            }
          end.reverse
        end

        def calculate_top_issues(validations)
          issue_counts = Hash.new(0)
          issue_details = {}

          validations.limit(100).each do |validation|
            next unless validation.issues.is_a?(Array)

            validation.issues.each do |issue|
              code = issue['code']
              issue_counts[code] += 1

              unless issue_details[code]
                issue_details[code] = {
                  code: code,
                  severity: issue['severity'],
                  category: issue['category'],
                  message: issue['message']
                }
              end
            end
          end

          issue_counts.sort_by { |_code, count| -count }.first(5).map do |code, count|
            issue_details[code].merge(count: count)
          end
        end
      end
    end
  end
end
