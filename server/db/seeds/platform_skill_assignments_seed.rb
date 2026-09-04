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
  # NOTE (IMP-dd2904d87d6d): seven previously-bound slugs never existed as
  # skills and were silently dropped for months — incident-analysis,
  # performance-tuning, devops-automation, content-localization, user-research,
  # compliance-review, security-audit. They are removed below (the seed now
  # fails loud on unknown slugs); authoring those specialist skills is tracked
  # as its own improvement offer. Re-add the binding WITH the skill.
  'Infrastructure Health Monitor' => %w[
    sre-incident-response devops-engineer security-analyst
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
    productivity product-management
  ],
  'Visual Design Assistant' => %w[
    marketing product-management
  ],
  'Research Analyst' => %w[
    technical-researcher data knowledge-system-curator
    business-search
  ],
  # Strategic Planner — planning/analysis domain skills. Previously inherited
  # SYSTEM-extension infra skills (system-platform-deploy etc.) via the
  # executors' binds_to (removed in the 2026-06-28 domain-purity audit). This
  # rebinds it to its OWN domain so it isn't left with zero skills.
  'Strategic Planner' => %w[
    product-management business-search technical-researcher data
  ],
  # Engineering hierarchy canonicals (HIER-P2B-ENG, ai_engineering_agents_seed).
  # The Platform Architect designs agents/teams/skills/prompts, so it binds the
  # four design skills; the Platform Developer binds Extension Developer (the
  # code-intelligence surface is a tool family, not a skill); the promoted
  # Documentation Specialist keeps the four bindings the demo dev-team seed gave
  # it, api-design included (it wrote the API reference docs).
  # The Release Manager's authority is its tool families alone.
  'Platform Architect' => %w[
    ai-agent-architect design-agent-team-from-intent skill-management agent-autonomy
  ],
  'Platform Developer' => %w[
    extension-developer
  ],
  'Documentation Specialist' => %w[
    documentation-writer knowledge-system-curator product-management api-design
  ],
  'Legal & Compliance Analyst' => %w[
    legal
  ],
  'Life Sciences Research Analyst' => %w[
    bio-research technical-researcher
  ],
  'Finance Operations Analyst' => %w[
    finance data
  ],
  'Sales Operations Specialist' => %w[
    sales marketing business-search
  ],
  'Customer Success Agent' => %w[
    customer-support knowledge-system-curator productivity
  ]
}

# Fail LOUD on unknown slugs (IMP-dd2904d87d6d): `next unless skill` silently
# dropped bindings, under-provisioning specialist agents for months. Mirrors
# the system extension's SkillBindings.validate! pattern — collect EVERY
# missing slug, one raise with the full list, before any row is written.
# Matches the loop's exact lookup (global + active): an inactive skill would
# otherwise pass validation and still be dropped silently.
bound_slugs = platform_skill_assignments.values.flatten.uniq
known_slugs = Ai::Skill.global.where(slug: bound_slugs, status: 'active').pluck(:slug)
missing_slugs = bound_slugs - known_slugs
if missing_slugs.any?
  raise "[PlatformSkills] #{missing_slugs.size} bound skill slug(s) have no active global skill: " \
        "#{missing_slugs.sort.join(', ')} — author the skill(s) or remove the binding(s). " \
        "Nothing was assigned."
end

platform_skill_assignments.each do |agent_name, slugs|
  agent = Ai::Agent.resolve_for(admin_account.id, name: agent_name)
  next unless agent

  slugs.each_with_index do |slug, idx|
    skill = Ai::Skill.global.find_by(slug: slug, status: 'active')
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
