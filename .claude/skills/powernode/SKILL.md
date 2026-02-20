# Powernode Platform Operations

Interact with the Powernode knowledge ecosystem and skill management via MCP tools.

## Routing

Based on the user's request, determine the domain and use the appropriate MCP tool:

### Knowledge Graph
- **Search**: `platform.search_knowledge_graph` (action=search, query, mode=hybrid/vector/keyword/graph)
- **Reason**: `platform.reason_knowledge_graph` (action=reason, query, max_hops)
- **Explore**: `platform.get_graph_node`, `platform.list_graph_nodes`, `platform.get_graph_neighbors`
- **Extract**: `platform.extract_to_knowledge_graph` (action=extract, text — runs LLM extraction pipeline to create nodes/edges)
- **Stats**: `platform.graph_statistics`

### Shared Knowledge
- **Search**: `platform.search_knowledge` (action=search_knowledge, query)
- **Create**: `platform.create_knowledge` (action=create_knowledge, title, content, content_type, tags)
- **Update**: `platform.update_knowledge` (action=update_knowledge, entry_id, content, tags)
- **Promote**: `platform.promote_knowledge` (action=promote_knowledge, entry_id)

### Compound Learnings
- **Query**: `platform.query_learnings` (action=query_learnings, query, category, scope)
- **Create**: `platform.create_learning` (action=create_learning, title, content, category)
- **Reinforce**: `platform.reinforce_learning` (action=reinforce_learning, learning_id)
- **Metrics**: `platform.learning_metrics`

### Skills
- **List/Search**: `platform.list_skills` (action=list_skills, search, category, status)
- **Get**: `platform.get_skill` (action=get_skill, skill_id)
- **Discover**: `platform.discover_skills` (action=discover_skills, task_context)
- **Create**: `platform.create_skill` (action=create_skill, name, description, category, system_prompt, commands, tags)
- **Update**: `platform.update_skill` (action=update_skill, skill_id, + fields to change)
- **Toggle**: `platform.toggle_skill` (action=toggle_skill, skill_id, enabled)
- **Delete**: `platform.delete_skill` (action=delete_skill, skill_id) — cannot delete system skills
- **Health**: `platform.skill_health`, `platform.skill_metrics`

## Guidelines
- Always search before creating to avoid duplicates (services auto-dedup at >=0.92 similarity but checking first is faster)
- Confirm destructive operations (delete, disable) with the user before executing
- Use categories consistently: pattern, anti_pattern, best_practice, discovery, fact, failure_mode
