# frozen_string_literal: true

# AiTeamOptimizeJob - Background team composition optimization
# Analyzes team skills, identifies gaps, and recommends improvements
class AiTeamOptimizeJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 2

  def execute(args = {})
    @account_id = args[:account_id] || args['account_id']
    @team_id = args[:team_id] || args['team_id']

    log_info "[AiTeamOptimizeJob] Starting optimization for team #{@team_id}"

    team_data = fetch_team
    agents_data = fetch_available_agents
    analysis = analyze_composition(team_data, agents_data)

    submit_results(analysis)

    log_info "[AiTeamOptimizeJob] Optimization complete for team #{@team_id}"
    analysis
  end

  private

  def fetch_team
    response = api_client.get("/api/v1/internal/ai/teams/#{@team_id}")
    raise "Team not found: #{@team_id}" unless response['success']

    response['data']
  end

  def fetch_available_agents
    response = api_client.get("/api/v1/internal/ai/agents?account_id=#{@account_id}")
    response['data'] || []
  end

  def analyze_composition(team_data, agents_data)
    members = team_data['members'] || []
    team_type = team_data['team_type']

    team_skills = members.flat_map { |m| m['capabilities'] || [] }.uniq
    common_needed_skills = %w[research analysis coding review testing documentation]
    missing_skills = common_needed_skills - team_skills
    coverage = team_skills.size.to_f / [common_needed_skills.size, 1].max

    skill_counts = members.flat_map { |m| m['capabilities'] || [] }.tally
    redundant_skills = skill_counts.select { |_, count| count > 2 }.keys

    recommendations = []

    if missing_skills.any?
      agents_data.each do |agent|
        agent_skills = agent['skills'] || agent['capabilities'] || []
        overlap = agent_skills & missing_skills
        next if overlap.empty?
        next if members.any? { |m| m['agent_id'] == agent['id'] }

        recommendations << {
          type: 'add_agent',
          agent_id: agent['id'],
          agent_name: agent['name'],
          fills_gaps: overlap,
          reason: "Adds missing skills: #{overlap.join(', ')}"
        }
      end
    end

    case team_type
    when 'hierarchical'
      has_lead = members.any? { |m| m['is_lead'] }
      unless has_lead
        recommendations << {
          type: 'assign_lead',
          reason: 'Hierarchical team requires a designated lead'
        }
      end
    when 'sequential'
      if members.size < 2
        recommendations << {
          type: 'add_members',
          reason: 'Sequential team requires at least 2 members'
        }
      end
    end

    {
      skill_coverage: (coverage * 100).round(1),
      team_skills: team_skills,
      missing_skills: missing_skills,
      redundant_skills: redundant_skills,
      recommendations: recommendations,
      gaps: missing_skills.map { |s| { skill: s, severity: 'medium' } }
    }
  end

  def submit_results(analysis)
    api_client.post(
      "/api/v1/internal/ai/teams/#{@team_id}/optimization_results",
      {
        recommendations: analysis[:recommendations],
        skill_coverage: analysis[:skill_coverage],
        gaps: analysis[:gaps]
      }
    )
  rescue StandardError => e
    log_error "[AiTeamOptimizeJob] Failed to submit results", e
  end
end
