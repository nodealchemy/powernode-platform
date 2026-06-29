# frozen_string_literal: true

# Platform-wide skill assignments — assigns skills to agents that are created by
# MANY different seeds (claude_agents, ai_utility, ai_dev_team, ai_concierge,
# autonomy_data). Loaded LAST in the demo section so every target agent already
# exists on the FIRST db:seed. (Previously this lived mid-way through
# ai_dev_team_seed, which runs before ai_concierge creates "Powernode Assistant"
# and before autonomy_data creates the industry agents — so a first seed skipped
# them and a second seed silently added their skills, breaking idempotency.)
admin_account = Account.find_by(name: "Powernode Admin")
unless admin_account
  Rails.logger.warn "[PlatformSkills] Admin account not found — skipping platform skill assignments"
  return
end

platform_skills_assigned = 0

platform_skill_assignments = {
  'Infrastructure Health Monitor' => %w[
    sre-incident-response devops-engineer incident-analysis
    performance-tuning security-analyst
  ],
  'Knowledge Graph Curator' => %w[
    knowledge-system-curator data skill-management
    business-search
  ],
  'Powernode Assistant' => %w[
    productivity knowledge-system-curator skill-management
    product-management powernode-dev
    design-skill-from-intent
    design-agent-team-from-intent
  ],
  'Process Automation Optimizer' => %w[
    devops-automation productivity incident-analysis
    product-management
  ],
  'Visual Design Assistant' => %w[
    content-localization marketing product-management
    user-research
  ],
  'Research Analyst' => %w[
    technical-researcher data knowledge-system-curator
    business-search user-research
  ],
  # Strategic Planner — planning/analysis domain skills. Previously inherited
  # SYSTEM-extension infra skills (system-platform-deploy etc.) via the
  # executors' binds_to (removed in the 2026-06-28 domain-purity audit). This
  # rebinds it to its OWN domain so it isn't left with zero skills.
  'Strategic Planner' => %w[
    product-management business-search technical-researcher data
  ],
  'Legal & Compliance Analyst' => %w[
    legal compliance-review security-audit
  ],
  'Life Sciences Research Analyst' => %w[
    bio-research technical-researcher
  ],
  'Finance Operations Analyst' => %w[
    finance data compliance-review
  ],
  'Sales Operations Specialist' => %w[
    sales marketing business-search
  ],
  'Customer Success Agent' => %w[
    customer-support knowledge-system-curator productivity
  ]
}

platform_skill_assignments.each do |agent_name, slugs|
  agent = Ai::Agent.resolve_for(admin_account.id, name: agent_name)
  next unless agent

  slugs.each_with_index do |slug, idx|
    skill = Ai::Skill.find_by(slug: slug, status: 'active')
    next unless skill

    Ai::AgentSkill.find_or_create_by!(
      ai_agent_id: agent.id,
      ai_skill_id: skill.id
    ) do |as|
      as.is_active = true
      as.priority = [idx / 3, 2].min
    end
    platform_skills_assigned += 1
  end
end

if platform_skills_assigned.positive?
  puts "  ✅ Platform-wide Skills Assigned: #{platform_skills_assigned}"
end
