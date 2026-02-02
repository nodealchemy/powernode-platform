# frozen_string_literal: true

module A2a
  module Skills
    class CommunitySkills
      class << self
        def register_agent(account:, user:, params:)
          agent = account.ai_agents.find(params[:agent_id])

          # Check if already registered
          existing = CommunityAgent.find_by(agent_id: agent.id)
          if existing.present?
            raise ArgumentError, "Agent already registered in community"
          end

          community_agent = CommunityAgent.create!(
            owner_account: account,
            agent: agent,
            published_by: user,
            name: params[:name],
            slug: params[:name].parameterize,
            description: params[:description],
            long_description: params[:long_description],
            category: params[:category],
            tags: params[:tags] || [],
            visibility: params[:visibility] || "public",
            status: "pending",
            protocol_version: "0.3",
            capabilities: build_capabilities(agent),
            published_at: Time.current
          )

          {
            community_agent_id: community_agent.id,
            slug: community_agent.slug,
            status: community_agent.status
          }
        end

        def discover_agents(account:, user:, params:)
          agents = CommunityAgent.where(status: "active")
                                 .where(visibility: %w[public unlisted])

          # Apply filters
          if params[:query].present?
            agents = agents.where(
              "name ILIKE :q OR description ILIKE :q",
              q: "%#{params[:query]}%"
            )
          end

          if params[:category].present?
            agents = agents.where(category: params[:category])
          end

          if params[:tags].present?
            agents = agents.where("tags && ARRAY[?]::varchar[]", params[:tags])
          end

          if params[:min_rating].present?
            agents = agents.where("avg_rating >= ?", params[:min_rating])
          end

          if params[:verified_only]
            agents = agents.where(verified: true)
          end

          # Order by reputation
          agents = agents.order(reputation_score: :desc, task_count: :desc)

          {
            agents: agents.limit(50).map(&:community_summary),
            total: agents.count
          }
        end

        def rate_agent(account:, user:, params:)
          community_agent = CommunityAgent.find(params[:community_agent_id])

          # Check for existing rating
          existing = CommunityAgentRating.find_by(
            community_agent: community_agent,
            account: account
          )

          if existing.present?
            existing.update!(
              rating: params[:rating],
              review: params[:review],
              edited_at: Time.current
            )
          else
            CommunityAgentRating.create!(
              community_agent: community_agent,
              account: account,
              user: user,
              a2a_task_id: params[:task_id],
              rating: params[:rating],
              review: params[:review],
              verified_usage: params[:task_id].present?
            )
          end

          # Update agent metrics
          community_agent.refresh_rating!

          { success: true }
        end

        def report_agent(account:, user:, params:)
          community_agent = CommunityAgent.find(params[:community_agent_id])

          report = CommunityAgentReport.create!(
            community_agent: community_agent,
            reported_by_account: account,
            reported_by_user: user,
            report_type: params[:report_type],
            description: params[:description],
            evidence: params[:evidence] || {},
            status: "pending"
          )

          {
            report_id: report.id
          }
        end

        private

        def build_capabilities(agent)
          {
            skills: agent.agent_card&.capabilities&.dig("skills") || [],
            streaming: agent.agent_card&.capabilities&.dig("streaming") || false,
            push_notifications: agent.agent_card&.capabilities&.dig("pushNotifications") || false
          }
        end
      end
    end
  end
end
