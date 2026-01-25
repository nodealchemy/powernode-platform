# frozen_string_literal: true

# Shared filtering, sorting, and pagination logic for AI controllers
#
# This concern provides standardized methods for:
# - Filtering resources (workflows, runs, templates, agents)
# - Sorting with configurable sort fields
# - Pagination using Kaminari
#
# Usage:
#   class WorkflowsController < ApplicationController
#     include Ai::ResourceFiltering
#
#     def index
#       workflows = apply_workflow_filters(base_scope)
#       workflows = apply_sorting(workflows, workflow_sort_fields)
#       workflows = apply_pagination(workflows)
#       render_success(items: workflows, pagination: pagination_data(workflows))
#     end
#   end
#
module Ai
  module ResourceFiltering
    extend ActiveSupport::Concern

    # =============================================================================
    # PAGINATION
    # =============================================================================

    # Apply pagination to a collection using Kaminari
    # @param collection [ActiveRecord::Relation] The collection to paginate
    # @param options [Hash] Options for pagination
    # @option options [Integer] :page The page number (default: params[:page] || 1)
    # @option options [Integer] :per_page Items per page (default: params[:per_page] || 25)
    # @return [ActiveRecord::Relation] Paginated collection
    def apply_pagination(collection, options = {})
      page = options[:page] || params[:page] || 1
      per_page = options[:per_page] || params[:per_page] || 25

      collection.page(page).per(per_page)
    end

    # Generate pagination metadata for API response
    # @param collection [ActiveRecord::Relation] Paginated collection
    # @return [Hash] Pagination metadata
    def pagination_data(collection)
      {
        current_page: collection.current_page,
        per_page: collection.limit_value,
        total_pages: collection.total_pages,
        total_count: collection.total_count
      }
    end

    # =============================================================================
    # SORTING
    # =============================================================================

    # Apply sorting to a collection
    # @param collection [ActiveRecord::Relation] The collection to sort
    # @param sort_fields [Hash] Map of allowed sort fields (param_name => column_name)
    # @param options [Hash] Sorting options
    # @option options [String] :default_sort_by Default sort field (default: 'created_at')
    # @option options [String] :default_sort_order Default sort order (default: 'desc')
    # @return [ActiveRecord::Relation] Sorted collection
    def apply_sorting(collection, sort_fields = {}, options = {})
      default_fields = {
        "name" => "name",
        "created_at" => "created_at",
        "updated_at" => "updated_at",
        "status" => "status"
      }

      valid_sort_fields = default_fields.merge(sort_fields)
      sort_by = params[:sort_by] || options[:default_sort_by] || "created_at"
      sort_order = params[:sort_order] || options[:default_sort_order] || "desc"

      sort_field = valid_sort_fields[sort_by] || "created_at"
      sort_direction = %w[asc desc].include?(sort_order&.downcase) ? sort_order.downcase : "desc"

      # Handle join-based sorting (e.g., "users.name")
      if sort_field.include?(".")
        table, column = sort_field.split(".")
        collection.order(Arel.sql("#{table}.#{column} #{sort_direction}"))
      else
        collection.order("#{sort_field} #{sort_direction}")
      end
    end

    # =============================================================================
    # WORKFLOW FILTERS
    # =============================================================================

    # Apply common filters to workflow queries
    # @param workflows [ActiveRecord::Relation] Base workflow query
    # @return [ActiveRecord::Relation] Filtered workflows
    def apply_workflow_filters(workflows)
      workflows = workflows.where(status: params[:status]) if params[:status].present?
      workflows = workflows.where(visibility: params[:visibility]) if params[:visibility].present?
      workflows = workflows.search_by_text(params[:search]) if params[:search].present? && workflows.respond_to?(:search_by_text)

      # Filter by is_template - only apply if explicitly set
      if params[:is_template].present?
        is_template_value = ActiveModel::Type::Boolean.new.cast(params[:is_template])
        workflows = workflows.where(is_template: is_template_value)
      end

      workflows
    end

    # =============================================================================
    # WORKFLOW RUN FILTERS
    # =============================================================================

    # Apply common filters to workflow run queries
    # @param runs [ActiveRecord::Relation] Base workflow run query
    # @return [ActiveRecord::Relation] Filtered runs
    def apply_run_filters(runs)
      runs = runs.where(ai_workflow_id: params[:workflow_id]) if params[:workflow_id].present?
      runs = runs.where(status: params[:status]) if params[:status].present?
      runs = runs.where(triggered_by_user_id: params[:user_id]) if params[:user_id].present?

      # Date range filters
      if params[:start_date].present?
        runs = runs.where("created_at >= ?", Date.parse(params[:start_date]))
      end

      if params[:end_date].present?
        runs = runs.where("created_at <= ?", Date.parse(params[:end_date]))
      end

      # ISO8601 timestamp filtering (used by worker cleanup jobs)
      if params[:before].present?
        runs = runs.where("created_at < ?", Time.parse(params[:before]))
      end

      if params[:limit].present?
        runs = runs.limit(params[:limit].to_i)
      end

      runs
    end

    # =============================================================================
    # TEMPLATE FILTERS
    # =============================================================================

    # Apply common filters to template queries
    # @param templates [ActiveRecord::Relation] Base template query
    # @return [ActiveRecord::Relation] Filtered templates
    def apply_template_filters(templates)
      templates = templates.where(category: params[:category]) if params[:category].present?
      templates = templates.where(difficulty_level: params[:difficulty_level]) if params[:difficulty_level].present?

      if params[:is_public].present?
        is_public_value = ActiveModel::Type::Boolean.new.cast(params[:is_public])
        templates = templates.where(is_public: is_public_value)
      end

      if params[:search].present?
        templates = templates.where(
          "name ILIKE :q OR description ILIKE :q",
          q: "%#{params[:search]}%"
        )
      end

      if params[:tags].present?
        tag_list = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].to_s.split(",")
        templates = templates.where("tags @> ARRAY[?]::varchar[]", tag_list)
      end

      templates
    end

    # =============================================================================
    # AGENT FILTERS
    # =============================================================================

    # Apply common filters to agent queries
    # @param agents [ActiveRecord::Relation] Base agent query
    # @param options [Hash] Additional filtering options
    # @option options [User] :current_user The current user (for my_agents filter)
    # @return [ActiveRecord::Relation] Filtered agents
    def apply_agent_filters(agents, options = {})
      agents = agents.where(status: params[:status]) if params[:status].present?
      agents = agents.where(agent_type: params[:agent_type]) if params[:agent_type].present?

      if params[:is_active].present?
        is_active_value = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        agents = agents.where(is_active: is_active_value)
      end

      # Filter to only user's own agents
      if params[:my_agents] == "true" && options[:current_user].present?
        agents = agents.where(creator: options[:current_user])
      end

      # Filter to only public agents
      if params[:public_only] == "true"
        agents = agents.where(is_public: true)
      end

      # Search by text - prefer model's search_by_text if available
      if params[:search].present?
        if agents.respond_to?(:search_by_text)
          agents = agents.search_by_text(params[:search])
        else
          agents = agents.where(
            "name ILIKE :q OR description ILIKE :q",
            q: "%#{params[:search]}%"
          )
        end
      end

      agents
    end

    # =============================================================================
    # EXECUTION FILTERS
    # =============================================================================

    # Apply common filters to execution queries (agent executions, workflow runs)
    # @param executions [ActiveRecord::Relation] Base execution query
    # @return [ActiveRecord::Relation] Filtered executions
    def apply_execution_filters(executions)
      executions = executions.where(status: params[:status]) if params[:status].present?
      executions = executions.where(user_id: params[:user_id]) if params[:user_id].present?

      # Date range filters
      if params[:start_date].present?
        executions = executions.where("created_at >= ?", Date.parse(params[:start_date]))
      end

      if params[:end_date].present?
        executions = executions.where("created_at <= ?", Date.parse(params[:end_date]))
      end

      executions
    end

    # =============================================================================
    # ANALYTICS TIME RANGE
    # =============================================================================

    # Parse time range parameter and return ActiveSupport::Duration
    # @return [ActiveSupport::Duration] Time range duration
    def parse_time_range
      case params[:time_range]
      when "1h" then 1.hour
      when "24h", "1d" then 24.hours
      when "7d" then 7.days
      when "30d" then 30.days
      when "90d" then 90.days
      when "1y" then 1.year
      else
        30.days # Default
      end
    end

    # Set time range instance variable (commonly used in before_action)
    def set_time_range
      @time_range = parse_time_range
    end

    # Generate time range info for API response
    # @return [Hash] Time range metadata
    def time_range_info
      {
        start: @time_range.ago.iso8601,
        end: Time.current.iso8601,
        period: params[:time_range] || "30d",
        duration_seconds: @time_range.to_i
      }
    end
  end
end
