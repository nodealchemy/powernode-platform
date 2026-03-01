# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ApiReferenceController < ApplicationController
        include AuditLogging

        before_action :validate_permissions

        SECTIONS = {
          "agents" => { description: "AI Agent CRUD, execution, skills", prefix: "/api/v1/ai/agents" },
          "teams" => { description: "Agent team management and execution", prefix: "/api/v1/ai/teams" },
          "workflows" => { description: "Workflow CRUD, execution, runs", prefix: "/api/v1/ai/workflows" },
          "providers" => { description: "AI provider and credential management", prefix: "/api/v1/ai/providers" },
          "git" => { description: "Git repositories, pipelines, runners", prefix: "/api/v1/devops/git" },
          "monitoring" => { description: "System health, metrics, alerts", prefix: "/api/v1/ai/monitoring" },
          "memory" => { description: "Memory pools and shared context", prefix: "/api/v1/ai/memory_pools" },
          "rag" => { description: "Knowledge bases and RAG queries", prefix: "/api/v1/ai/rag" },
          "execution" => { description: "Parallel execution, worktrees, resources", prefix: "/api/v1/ai/worktree_sessions" },
          "conversations" => { description: "AI conversations and messaging", prefix: "/api/v1/ai/conversations" }
        }.freeze

        # GET /api/v1/ai/api_reference
        def index
          sections = SECTIONS.map do |key, info|
            endpoints = routes_for_section(info[:prefix])
            {
              section: key,
              description: info[:description],
              endpoint_count: endpoints.count,
              base_path: info[:prefix]
            }
          end

          render_success(sections: sections, total_sections: sections.count)
        end

        # GET /api/v1/ai/api_reference/search
        def search
          query = params[:q]&.downcase
          return render_error("Query parameter 'q' is required", status: :bad_request) if query.blank?

          results = []
          SECTIONS.each do |key, info|
            endpoints = routes_for_section(info[:prefix])
            matches = endpoints.select do |ep|
              ep[:path].downcase.include?(query) ||
                ep[:action].downcase.include?(query) ||
                key.include?(query)
            end
            results.concat(matches.map { |ep| ep.merge(section: key) })
          end

          render_success(query: query, results: results, count: results.count)
        end

        # GET /api/v1/ai/api_reference/:section
        def show
          section_key = params[:section]
          section_info = SECTIONS[section_key]
          return render_error("Section not found: #{section_key}", status: :not_found) unless section_info

          endpoints = routes_for_section(section_info[:prefix])

          render_success(
            section: section_key,
            description: section_info[:description],
            base_path: section_info[:prefix],
            endpoints: endpoints,
            endpoint_count: endpoints.count
          )
        end

        private

        def validate_permissions
          return if current_worker

          require_permission("ai.agents.read")
        end

        def routes_for_section(prefix)
          Rails.application.routes.routes.select do |route|
            path = route.path.spec.to_s.gsub("(.:format)", "")
            path.start_with?(prefix)
          end.map do |route|
            path = route.path.spec.to_s.gsub("(.:format)", "")
            {
              method: (route.verb.presence || "GET"),
              path: path,
              action: route.defaults[:action] || "",
              controller: route.defaults[:controller] || ""
            }
          end.uniq { |ep| [ep[:method], ep[:path]] }
        end
      end
    end
  end
end
