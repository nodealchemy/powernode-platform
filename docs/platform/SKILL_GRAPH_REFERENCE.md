# Skill Graph Reference

**Skills registry, agent-skill mapping, lifecycle management, and gap detection**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

The Skill Graph system manages reusable capabilities that agents can possess and execute. Skills are versioned, categorized, and linked to agents via an assignment model. The system includes conflict detection, proposal workflows, gap detection, and automated lifecycle management.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::Skill` | Core skill definition with category, status, and execution context |
| `Ai::AgentSkill` | Many-to-many link between agents and skills |
| `Ai::SkillConflict` | Detected conflicts between overlapping skills |
| `Ai::SkillProposal` | Workflow for proposing new skills (submit → approve → create) |
| `Ai::SkillUsageRecord` | Tracks skill execution outcomes |
| `Ai::SkillVersion` | Version history with A/B testing support |
| `LifecycleService` | End-to-end skill lifecycle (research → propose → approve → create) |

---

## Models

### Ai::Skill

Core skill definition with 21 categories.

```ruby
CATEGORIES = %w[
  code_generation code_review testing debugging deployment
  documentation analysis communication planning research
  data_processing security monitoring optimization
  integration automation design architecture
  project_management devops operations
]
STATUSES = %w[draft active deprecated archived]

belongs_to :account, optional: true
belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", optional: true
belongs_to :parent_skill, class_name: "Ai::Skill", optional: true
has_many :child_skills, class_name: "Ai::Skill"
has_many :agent_skills, class_name: "Ai::AgentSkill"
has_many :agents, through: :agent_skills
has_many :versions, class_name: "Ai::SkillVersion"
has_many :usage_records, class_name: "Ai::SkillUsageRecord"
has_many :proposals, class_name: "Ai::SkillProposal"
has_many :conflicts_as_a, class_name: "Ai::SkillConflict"
has_many :conflicts_as_b, class_name: "Ai::SkillConflict"
```

**Key fields:** `name`, `slug` (unique), `category`, `status`, `description`, `execution_context` (JSON), `effectiveness_score`, `usage_count`

**Key methods:**
- `activate!` / `deactivate!` — status transitions
- `record_usage!` — increments usage counter
- `recalculate_effectiveness!` — updates effectiveness score from usage records
- `usage_success_rate` — ratio of successful executions
- `active_conflicts` — returns unresolved conflicts
- `command_definitions` — returns MCP tool definitions for the skill

### Ai::AgentSkill

Links agents to skills with ordering.

```ruby
belongs_to :agent, class_name: "Ai::Agent"
belongs_to :skill, class_name: "Ai::Skill"

# Unique: one skill assignment per agent
validates :ai_skill_id, uniqueness: { scope: :ai_agent_id }
```

### Ai::SkillConflict

Detected conflicts between overlapping or contradictory skills.

```ruby
CONFLICT_TYPES = %w[overlap contradiction dependency version_mismatch naming]
SEVERITIES = %w[low medium high critical]
STATUSES = %w[detected acknowledged resolved dismissed]
SEVERITY_WEIGHTS = { "low" => 1, "medium" => 2, "high" => 4, "critical" => 8 }

belongs_to :skill_a, class_name: "Ai::Skill"
belongs_to :skill_b, class_name: "Ai::Skill", optional: true
belongs_to :resolved_by, class_name: "User", optional: true
```

**Key methods:**
- `resolve!` — marks conflict as resolved
- `dismiss!` — marks conflict as dismissed
- `calculate_priority!` — computes priority from severity weight

### Ai::SkillProposal

Workflow for proposing, reviewing, and creating new skills.

```ruby
STATUSES = %w[draft submitted under_review approved rejected created]

belongs_to :proposed_by_agent, class_name: "Ai::Agent", optional: true
belongs_to :proposed_by_user, class_name: "User", optional: true
belongs_to :reviewed_by, class_name: "User", optional: true
belongs_to :created_skill, class_name: "Ai::Skill", optional: true
has_many :child_proposals
```

**State machine:** `submit!` → `approve!` / `reject!` → `mark_created!`

**Key methods:**
- `can_auto_approve?` — checks if proposal meets auto-approval criteria
- `proposal_summary` — serialization helper

### Ai::SkillUsageRecord

Tracks individual skill execution outcomes.

```ruby
OUTCOMES = %w[success failure error timeout]

belongs_to :ai_skill
belongs_to :ai_agent, optional: true
```

### Ai::SkillVersion

Version history for skills with A/B testing support.

```ruby
CHANGE_TYPES = %w[major minor patch hotfix experimental]

belongs_to :ai_skill
belongs_to :created_by_agent, class_name: "Ai::Agent", optional: true
```

**Key methods:**
- `record_outcome!(success:)` — tracks outcome for effectiveness comparison
- `activate!` — makes this version the active one
- `version_summary` — serialization helper

---

## Services

### LifecycleService

End-to-end skill lifecycle management.

```ruby
service = Ai::SkillGraph::LifecycleService.new(account: account)

# Research and propose a new skill
proposal = service.research_and_propose(
  "Kubernetes deployment automation",
  requesting_agent: agent,
  requesting_user: user
)

# Submit for review
service.submit_proposal(proposal.id)

# Approve and create
service.approve_proposal(proposal.id, reviewer: admin_user)
skill = service.create_skill_from_proposal(proposal.id)
```

**Pipeline:**
1. **Research** — uses `ResearchService` to analyze the topic
2. **Propose** — creates `SkillProposal` with inferred category and confidence
3. **Submit** — validates and moves to review queue
4. **Approve** — reviewer approves; auto-creates sub-proposals for dependencies
5. **Create** — builds `Skill`, initial `SkillVersion`, and dependency edges in knowledge graph

### Other Skill Services

| Service | Purpose |
|---------|---------|
| `ConflictDetectionService` | Scans for overlapping skills, runs daily at 4:15 AM |
| `HealthScoreService` | Calculates skill health from usage patterns and conflicts |
| `EvolutionService` | Tracks skill improvement over versions |
| `OptimizationService` | Suggests skill configuration improvements |
| `AutoRepairService` | Automatically resolves simple conflicts |
| `BridgeService` | Bridges skills to knowledge graph nodes |
| `TraversalService` | Graph traversal for skill dependency chains |
| `TeamCoverageService` | Analyzes skill coverage across agent teams |
| `ResearchService` | AI-powered skill research and analysis |
| `SelfLearningService` | Skill improvement from usage feedback |
| `ContextEnrichmentService` | Enriches skill execution context |

---

## Automated Lifecycle Jobs

| Job | Schedule | Action |
|-----|----------|--------|
| Conflict scan | 4:15 AM daily | Detects new skill conflicts |
| Stale decay | 5:00 AM weekly | Reduces effectiveness of unused skills |
| Re-embedding | 5:00 AM weekly | Updates skill embeddings for discovery |
| Gap detection | 3:00 AM monthly | Identifies missing capabilities across teams |

---

## Skill Discovery

Skills can be discovered via MCP tools:

```ruby
# Find skills matching a task description
platform.discover_skills(description: "deploy to kubernetes")

# Get full execution context for a skill
platform.get_skill_context(skill_id: "uuid")

# List all skills with filters
platform.list_skills(category: "deployment", status: "active")
```

---

## Key Files

| File | Path |
|------|------|
| Skill Model | `server/app/models/ai/skill.rb` |
| Agent Skill Model | `server/app/models/ai/agent_skill.rb` |
| Skill Conflict Model | `server/app/models/ai/skill_conflict.rb` |
| Skill Proposal Model | `server/app/models/ai/skill_proposal.rb` |
| Skill Usage Record Model | `server/app/models/ai/skill_usage_record.rb` |
| Skill Version Model | `server/app/models/ai/skill_version.rb` |
| Lifecycle Service | `server/app/services/ai/skill_graph/lifecycle_service.rb` |
| Conflict Detection | `server/app/services/ai/skill_graph/conflict_detection_service.rb` |
| Health Score | `server/app/services/ai/skill_graph/health_score_service.rb` |
| Team Coverage | `server/app/services/ai/skill_graph/team_coverage_service.rb` |
| Skill Service | `server/app/services/ai/skill_service.rb` |
| Skill Controller | `server/app/controllers/api/v1/ai/skills_controller.rb` |
| Skill Graph Controller | `server/app/controllers/api/v1/ai/skill_graph_controller.rb` |
