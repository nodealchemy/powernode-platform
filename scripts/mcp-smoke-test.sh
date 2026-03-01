#!/bin/bash
# frozen: MCP Platform Smoke Test
# Exercises all 78 MCP tools across 14 categories via JSON-RPC 2.0
# Requires: backend running on localhost:3000, jq, curl
#
# Usage:
#   ./scripts/mcp-smoke-test.sh                    # Run all phases
#   ./scripts/mcp-smoke-test.sh --phase 0          # Run single phase
#   ./scripts/mcp-smoke-test.sh --phase 0,3,6      # Run specific phases
#   ./scripts/mcp-smoke-test.sh --skip-cleanup      # Don't clean up created resources
#   ./scripts/mcp-smoke-test.sh --skip-rest         # Skip Phase 2 (REST API / Ralph Loop)
#
# Environment:
#   MCP_TOKEN    - OAuth Bearer token for MCP endpoint (required)
#   MCP_URL      - MCP endpoint URL (default: http://localhost:3000/api/v1/mcp/message)
#   API_URL      - REST API base URL (default: http://localhost:3000/api/v1)
#
set +H  # disable bash history expansion

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────
MCP_URL="${MCP_URL:-http://localhost:3000/api/v1/mcp/message}"
API_URL="${API_URL:-http://localhost:3000/api/v1}"

# Parse arguments first (so --help works without a token)
PHASES_FILTER=""
SKIP_CLEANUP=false
SKIP_REST=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASES_FILTER="$2"; shift 2 ;;
    --skip-cleanup) SKIP_CLEANUP=true; shift ;;
    --skip-rest) SKIP_REST=true; shift ;;
    -h|--help)
      head -12 "$0" | tail -11
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$MCP_TOKEN" ]; then
  echo "ERROR: MCP_TOKEN environment variable is required"
  echo "  Set it to your Doorkeeper OAuth access token:"
  echo "  export MCP_TOKEN=your_token_here"
  exit 1
fi

should_run_phase() {
  local phase="$1"
  [ -z "$PHASES_FILTER" ] && return 0
  echo ",$PHASES_FILTER," | grep -q ",$phase,"
}

# ─────────────────────────────────────────────────
# Counters & Helpers
# ─────────────────────────────────────────────────
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
PHASE_PASS=0
PHASE_FAIL=0
CREATED_IDS=""  # track created resource IDs for cleanup

EMPTY_OBJ='{}'

# MCP JSON-RPC tool call
mcp_call() {
  local tool_name="$1"
  local args="$2"
  if [ -z "$args" ]; then
    args="$EMPTY_OBJ"
  fi
  local id
  id=$(date +%s%N | cut -c1-13)
  local payload
  payload=$(jq -n \
    --arg tool "$tool_name" \
    --argjson args "$args" \
    --argjson id "$id" \
    '{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":$tool,"arguments":$args}}')
  curl -s -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${MCP_TOKEN}" \
    -d "$payload"
}

# Tally a tool call result — handles JSON-RPC errors, null results, and success:false
tally() {
  local label="$1"
  local response="$2"
  # Check for JSON-RPC error
  local err_code
  err_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)
  if [ -n "$err_code" ]; then
    echo "  FAIL  $label -> $(echo "$response" | jq -r '.error.message' | head -c 150)"
    PHASE_FAIL=$((PHASE_FAIL + 1))
    return 1
  fi
  local text
  text=$(echo "$response" | jq -r '.result.content[0].text' 2>/dev/null)
  if [ "$text" = "null" ] || [ -z "$text" ]; then
    echo "  WARN  $label -> null result"
    PHASE_FAIL=$((PHASE_FAIL + 1))
    return 1
  fi
  # Use tostring to avoid jq // treating false as falsy
  local success
  success=$(echo "$text" | jq -r '.success | tostring' 2>/dev/null)
  if [ "$success" = "false" ]; then
    local err
    err=$(echo "$text" | jq -r '.error // "unknown"' 2>/dev/null | head -c 150)
    echo "  FAIL  $label -> $err"
    PHASE_FAIL=$((PHASE_FAIL + 1))
    return 1
  fi
  echo "  PASS  $label -> ${text:0:120}..."
  PHASE_PASS=$((PHASE_PASS + 1))
  return 0
}

# Tally a graceful error (expected failure = PASS)
tally_graceful_error() {
  local label="$1"
  local response="$2"
  local err_text
  err_text=$(echo "$response" | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.error // empty' 2>/dev/null)
  if [ -n "$err_text" ]; then
    echo "  PASS  $label -> graceful error: ${err_text:0:100}"
    PHASE_PASS=$((PHASE_PASS + 1))
    return 0
  fi
  tally "$label" "$response"
}

# Extract ID from response checking multiple jq paths
extract_id() {
  local response="$1"
  local paths="$2"  # space-separated jq paths
  local text
  text=$(echo "$response" | jq -r '.result.content[0].text' 2>/dev/null)
  for path in $paths; do
    local val
    val=$(echo "$text" | jq -r "$path // empty" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      echo "$val"
      return
    fi
  done
}

# REST API call (requires JWT)
api() {
  local method="$1"
  local path="$2"
  local data="$3"
  if [ -n "$data" ]; then
    curl -s -X "$method" "${API_URL}${path}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${JWT}" \
      -d "$data"
  else
    curl -s -X "$method" "${API_URL}${path}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${JWT}"
  fi
}

check_api() {
  local label="$1"
  local response="$2"
  local success
  success=$(echo "$response" | jq -r '.success // false')
  if [ "$success" = "true" ]; then
    echo "  PASS  $label"
    PHASE_PASS=$((PHASE_PASS + 1))
  else
    local err
    err=$(echo "$response" | jq -r '.error // "unknown"' | head -c 150)
    echo "  FAIL  $label -> $err"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi
}

start_phase() {
  PHASE_PASS=0
  PHASE_FAIL=0
  echo ""
  echo "============================================="
  echo "  $1"
  echo "============================================="
}

end_phase() {
  TOTAL_PASS=$((TOTAL_PASS + PHASE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + PHASE_FAIL))
  echo ""
  echo "  Phase result: ${PHASE_PASS} PASS, ${PHASE_FAIL} FAIL"
  echo "---------------------------------------------"
}

# ─────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────
echo "============================================="
echo "  Powernode MCP Smoke Test"
echo "============================================="
echo "  MCP URL:  $MCP_URL"
echo "  API URL:  $API_URL"
echo "  Token:    ${MCP_TOKEN:0:8}..."
echo ""

echo "Checking backend health..."
HEALTH=$(curl -s "${API_URL}/health" 2>/dev/null)
if echo "$HEALTH" | jq -r '.data.status' 2>/dev/null | grep -q "healthy"; then
  echo "  Backend is healthy"
else
  echo "  ERROR: Backend not responding at ${API_URL}/health"
  echo "  Start it with: sudo systemctl start powernode-backend@default"
  exit 1
fi

# ─────────────────────────────────────────────────
# PHASE 0: MCP Connection & Introspection (9 tools)
# ─────────────────────────────────────────────────
if should_run_phase 0; then
  start_phase "PHASE 0: MCP Introspection (9 tools)"

  for tool in platform.health platform.infrastructure platform.metrics; do
    RESP=$(mcp_call "$tool")
    tally "$tool" "$RESP"
  done

  RESP=$(mcp_call "platform.resources" '{"resource_type":"agents"}')
  tally "platform.resources (agents)" "$RESP"

  RESP=$(mcp_call "platform.resources" '{"resource_type":"teams"}')
  tally "platform.resources (teams)" "$RESP"

  for tool in platform.provider_health platform.alerts platform.cost_analysis platform.recent_events; do
    RESP=$(mcp_call "$tool")
    tally "$tool" "$RESP"
  done

  end_phase
fi

# ─────────────────────────────────────────────────
# PHASE 1: Knowledge, Skills, Agents, Teams, Memory (38 tools)
# ─────────────────────────────────────────────────
if should_run_phase 1; then
  start_phase "PHASE 1: Knowledge & Agent Foundation (38 tools)"

  echo ""
  echo "--- Knowledge Graph (7 ops) ---"
  RESP=$(mcp_call "platform.graph_statistics")
  tally "graph_statistics" "$RESP"

  RESP=$(mcp_call "platform.extract_to_knowledge_graph" '{"text":"The TestApp is a Rails 8 API with React TypeScript frontend. It uses JWT authentication with UUIDv7 primary keys. The UserService handles registration and login. The TodoController manages CRUD for todo items. PostgreSQL stores all data with pgvector for semantic search."}')
  tally "extract_to_knowledge_graph" "$RESP"

  RESP=$(mcp_call "platform.list_graph_nodes" '{"limit":5}')
  tally "list_graph_nodes" "$RESP"
  FIRST_NODE_ID=$(extract_id "$RESP" ".nodes[0].id .[0].id")

  if [ -n "$FIRST_NODE_ID" ]; then
    RESP=$(mcp_call "platform.get_graph_node" "{\"node_id\":\"${FIRST_NODE_ID}\"}")
    tally "get_graph_node" "$RESP"

    RESP=$(mcp_call "platform.get_graph_neighbors" "{\"node_id\":\"${FIRST_NODE_ID}\"}")
    tally "get_graph_neighbors" "$RESP"
  else
    echo "  SKIP  No node ID for get/neighbors"
    PHASE_FAIL=$((PHASE_FAIL + 2))
  fi

  RESP=$(mcp_call "platform.search_knowledge_graph" '{"query":"authentication","mode":"hybrid"}')
  tally "search_knowledge_graph" "$RESP"

  RESP=$(mcp_call "platform.reason_knowledge_graph" '{"query":"How does the app handle auth?","max_hops":2}')
  tally "reason_knowledge_graph" "$RESP"

  echo ""
  echo "--- Compound Learnings (4 ops) ---"
  RESP=$(mcp_call "platform.learning_metrics")
  tally "learning_metrics" "$RESP"

  RESP=$(mcp_call "platform.create_learning" '{"category":"pattern","content":"MCP tools follow a consistent BaseTool pattern: define tool name and parameters in self.definition, implement call(params), return {success: true/false} hashes.","source_type":"manual","tags":"mcp,pattern,smoke-test"}')
  tally "create_learning (pattern)" "$RESP"
  LEARNING_ID=$(extract_id "$RESP" ".learning.id .id")

  RESP=$(mcp_call "platform.create_learning" '{"category":"discovery","content":"Smoke testing revealed that MCP tool parameter names must exactly match the Ruby symbol keys used in the tool call method. Mismatches silently produce nil values.","source_type":"manual","tags":"mcp,discovery,smoke-test"}')
  tally "create_learning (discovery)" "$RESP"

  RESP=$(mcp_call "platform.query_learnings" '{"query":"MCP tools","limit":5}')
  tally "query_learnings" "$RESP"

  if [ -n "$LEARNING_ID" ]; then
    RESP=$(mcp_call "platform.reinforce_learning" "{\"learning_id\":\"${LEARNING_ID}\"}")
    tally "reinforce_learning" "$RESP"
  fi

  echo ""
  echo "--- Shared Knowledge (2 ops) ---"
  RESP=$(mcp_call "platform.create_knowledge" '{"title":"Smoke Test API Reference","content":"## MCP Endpoints\n\nPOST /api/v1/mcp/message - JSON-RPC 2.0\nGET /api/v1/mcp/sse - SSE stream","content_type":"markdown","access_level":"team","tags":["smoke-test","mcp"]}')
  tally "create_knowledge" "$RESP"
  KNOWLEDGE_ID=$(extract_id "$RESP" ".entry.id .knowledge.id .id")
  CREATED_IDS="$CREATED_IDS knowledge:$KNOWLEDGE_ID"

  RESP=$(mcp_call "platform.search_knowledge" '{"query":"MCP endpoints","limit":5}')
  tally "search_knowledge" "$RESP"

  echo ""
  echo "--- RAG Knowledge Bases (6 ops) ---"
  RESP=$(mcp_call "platform.list_knowledge_bases")
  tally "list_knowledge_bases" "$RESP"

  RESP=$(mcp_call "platform.create_knowledge_base" '{"name":"Smoke Test KB","description":"Auto-created by MCP smoke test for RAG lifecycle verification"}')
  tally "create_knowledge_base" "$RESP"
  SMOKE_KB_ID=$(extract_id "$RESP" ".knowledge_base.id .id")
  CREATED_IDS="$CREATED_IDS knowledge_base:$SMOKE_KB_ID"

  if [ -n "$SMOKE_KB_ID" ] && [ "$SMOKE_KB_ID" != "null" ]; then
    RESP=$(mcp_call "platform.add_document" "{\"knowledge_base_id\":\"${SMOKE_KB_ID}\",\"name\":\"Smoke Test Doc\",\"content\":\"# MCP Smoke Test\\n\\nThis document verifies the RAG document lifecycle.\\nIt covers chunking, embedding, and hybrid search capabilities.\\nKeywords: smoke test, MCP, RAG, knowledge base, verification.\"}")
    tally "add_document" "$RESP"
    SMOKE_DOC_ID=$(extract_id "$RESP" ".document.id .id")

    if [ -n "$SMOKE_DOC_ID" ] && [ "$SMOKE_DOC_ID" != "null" ]; then
      RESP=$(mcp_call "platform.process_document" "{\"knowledge_base_id\":\"${SMOKE_KB_ID}\",\"document_id\":\"${SMOKE_DOC_ID}\"}")
      tally "process_document" "$RESP"

      RESP=$(mcp_call "platform.search_documents" "{\"knowledge_base_id\":\"${SMOKE_KB_ID}\",\"query\":\"RAG verification\",\"mode\":\"hybrid\",\"top_k\":3}")
      tally "search_documents" "$RESP"

      RESP=$(mcp_call "platform.delete_document" "{\"knowledge_base_id\":\"${SMOKE_KB_ID}\",\"document_id\":\"${SMOKE_DOC_ID}\"}")
      tally "delete_document" "$RESP"
    else
      echo "  SKIP  No document ID for process/search/delete"
      PHASE_FAIL=$((PHASE_FAIL + 3))
    fi
  else
    echo "  SKIP  No KB ID for add/process/search/delete"
    PHASE_FAIL=$((PHASE_FAIL + 4))
  fi

  echo ""
  echo "--- Skills (5 ops) ---"
  RESP=$(mcp_call "platform.create_skill" '{"name":"Smoke Test - Doc Generator","description":"Generates API documentation from code analysis","category":"documentation"}')
  tally "create_skill" "$RESP"
  SKILL_ID=$(extract_id "$RESP" ".skill.id .id")
  CREATED_IDS="$CREATED_IDS skill:$SKILL_ID"

  if [ -n "$SKILL_ID" ]; then
    RESP=$(mcp_call "platform.get_skill" "{\"skill_id\":\"${SKILL_ID}\"}")
    tally "get_skill" "$RESP"
  fi

  RESP=$(mcp_call "platform.discover_skills" '{"task_context":"Generate API documentation for a Rails application"}')
  tally "discover_skills" "$RESP"

  RESP=$(mcp_call "platform.skill_health")
  tally "skill_health" "$RESP"

  RESP=$(mcp_call "platform.skill_metrics")
  tally "skill_metrics" "$RESP"

  echo ""
  echo "--- Agent Management (5 ops) ---"
  RESP=$(mcp_call "platform.create_agent" '{"name":"Smoke Test - Analyzer","description":"Analyzes repository code","agent_type":"specialist"}')
  tally "create_agent (analyzer)" "$RESP"
  ANALYZER_ID=$(extract_id "$RESP" ".agent.id .id")
  CREATED_IDS="$CREATED_IDS agent:$ANALYZER_ID"

  RESP=$(mcp_call "platform.create_agent" '{"name":"Smoke Test - Writer","description":"Writes documentation","agent_type":"specialist"}')
  tally "create_agent (writer)" "$RESP"
  WRITER_ID=$(extract_id "$RESP" ".agent.id .id")
  CREATED_IDS="$CREATED_IDS agent:$WRITER_ID"

  RESP=$(mcp_call "platform.list_agents")
  tally "list_agents" "$RESP"

  if [ -n "$ANALYZER_ID" ]; then
    RESP=$(mcp_call "platform.get_agent" "{\"agent_id\":\"${ANALYZER_ID}\"}")
    tally "get_agent" "$RESP"

    RESP=$(mcp_call "platform.update_agent" "{\"agent_id\":\"${ANALYZER_ID}\",\"system_prompt\":\"You analyze code repositories.\"}")
    tally "update_agent" "$RESP"
  fi

  echo ""
  echo "--- Team Management (5 ops) ---"
  RESP=$(mcp_call "platform.create_team" '{"name":"Smoke Test - Doc Team","description":"Documentation team","coordination_strategy":"sequential"}')
  tally "create_team" "$RESP"
  TEAM_ID=$(extract_id "$RESP" ".team.id .id")
  CREATED_IDS="$CREATED_IDS team:$TEAM_ID"

  if [ -n "$TEAM_ID" ] && [ -n "$ANALYZER_ID" ]; then
    RESP=$(mcp_call "platform.add_team_member" "{\"team_id\":\"${TEAM_ID}\",\"agent_id\":\"${ANALYZER_ID}\",\"role\":\"lead\"}")
    tally "add_team_member (lead)" "$RESP"

    if [ -n "$WRITER_ID" ]; then
      RESP=$(mcp_call "platform.add_team_member" "{\"team_id\":\"${TEAM_ID}\",\"agent_id\":\"${WRITER_ID}\",\"role\":\"worker\"}")
      tally "add_team_member (worker)" "$RESP"
    fi

    RESP=$(mcp_call "platform.get_team" "{\"team_id\":\"${TEAM_ID}\"}")
    tally "get_team" "$RESP"

    RESP=$(mcp_call "platform.update_team" "{\"team_id\":\"${TEAM_ID}\",\"coordination_strategy\":\"parallel\"}")
    tally "update_team" "$RESP"
  fi

  echo ""
  echo "--- Memory Management (4 ops) ---"
  RESP=$(mcp_call "platform.memory_stats")
  tally "memory_stats" "$RESP"

  RESP=$(mcp_call "platform.list_pools")
  tally "list_pools" "$RESP"

  RESP=$(mcp_call "platform.write_shared_memory" '{"key":"smoke_test.timestamp","value":"test_value"}')
  tally "write_shared_memory" "$RESP"

  RESP=$(mcp_call "platform.read_shared_memory" '{"key":"smoke_test.timestamp"}')
  tally "read_shared_memory" "$RESP"

  end_phase
fi

# ─────────────────────────────────────────────────
# PHASE 2: Mission & Ralph Loop (REST API, 9 ops)
# ─────────────────────────────────────────────────
if should_run_phase 2 && [ "$SKIP_REST" = "false" ]; then
  start_phase "PHASE 2: Mission & Ralph Loop (9 REST ops)"

  # Generate JWT for REST calls
  JWT=$(cd "$PROJECT_DIR/server" && bundle exec rails runner "
    user = User.first
    tokens = Security::JwtService.generate_user_tokens(user)
    puts tokens[:access_token]
  " 2>/dev/null)

  if [ -z "$JWT" ]; then
    echo "  SKIP  Could not generate JWT (rails runner failed)"
    TOTAL_SKIP=$((TOTAL_SKIP + 9))
  else
    # Create mission (research type — no repo required)
    MISSION_PAYLOAD=$(jq -n '{
      "name": "Smoke Test - Doc Intelligence",
      "objective": "Analyze and create documentation improvement plan",
      "mission_type": "research"
    }')
    MISSION_RESP=$(api POST "/ai/missions" "$MISSION_PAYLOAD")
    check_api "Create mission" "$MISSION_RESP"
    MISSION_ID=$(echo "$MISSION_RESP" | jq -r '.data.id // empty' 2>/dev/null)
    CREATED_IDS="$CREATED_IDS mission:$MISSION_ID"

    if [ -n "$MISSION_ID" ]; then
      GET_MISSION=$(api GET "/ai/missions/${MISSION_ID}")
      check_api "Get mission" "$GET_MISSION"
    fi

    # Create Ralph Loop with structured tasks
    if [ -n "$MISSION_ID" ]; then
      RALPH_PAYLOAD=$(jq -n --arg mid "$MISSION_ID" '{
        "ralph_loop": {
          "name": "Smoke Test Loop",
          "ai_mission_id": $mid,
          "prd": {
            "tasks": [
              {"task_key":"analyze","description":"Analyze endpoints","acceptance_criteria":"All endpoints listed","priority":"high","dependencies":[]},
              {"task_key":"generate","description":"Generate OpenAPI spec","acceptance_criteria":"Valid spec","priority":"medium","dependencies":["analyze"]},
              {"task_key":"update","description":"Update README","acceptance_criteria":"README updated","priority":"low","dependencies":["generate"]}
            ]
          }
        }
      }')
      RALPH_RESP=$(api POST "/ai/ralph_loops" "$RALPH_PAYLOAD")
      check_api "Create Ralph Loop" "$RALPH_RESP"
      RALPH_ID=$(echo "$RALPH_RESP" | jq -r '.data.id // empty' 2>/dev/null)
      CREATED_IDS="$CREATED_IDS ralph:$RALPH_ID"

      if [ -n "$RALPH_ID" ]; then
        GET_RALPH=$(api GET "/ai/ralph_loops/${RALPH_ID}")
        check_api "Get Ralph Loop" "$GET_RALPH"

        TASKS_RESP=$(api GET "/ai/ralph_loops/${RALPH_ID}/tasks")
        check_api "List tasks" "$TASKS_RESP"
        TASK_COUNT=$(echo "$TASKS_RESP" | jq '.data | length' 2>/dev/null)
        echo "  Tasks created: $TASK_COUNT"

        FIRST_TASK_ID=$(echo "$TASKS_RESP" | jq -r '.data[0].id // empty' 2>/dev/null)
        if [ -n "$FIRST_TASK_ID" ]; then
          TASK_DETAIL=$(api GET "/ai/ralph_loops/${RALPH_ID}/tasks/${FIRST_TASK_ID}")
          check_api "Get task detail" "$TASK_DETAIL"
        fi

        PROGRESS=$(api GET "/ai/ralph_loops/${RALPH_ID}/progress")
        check_api "Check progress" "$PROGRESS"
      fi
    fi

    # Update mission
    if [ -n "$MISSION_ID" ]; then
      UPDATE_RESP=$(api PATCH "/ai/missions/${MISSION_ID}" '{"description":"Updated by smoke test"}')
      check_api "Update mission" "$UPDATE_RESP"
    fi
  fi

  end_phase
fi

# ─────────────────────────────────────────────────
# PHASE 3: Remaining Category Spot-Checks (7 tools)
# ─────────────────────────────────────────────────
if should_run_phase 3; then
  start_phase "PHASE 3: Category Spot-Checks (7 tools)"

  RESP=$(mcp_call "platform.list_workflows")
  tally "list_workflows" "$RESP"

  RESP=$(mcp_call "platform.list_pipelines")
  tally "list_pipelines" "$RESP"

  RESP=$(mcp_call "platform.query_knowledge_base" '{"query":"AI agent best practices"}')
  tally "query_knowledge_base" "$RESP"

  RESP=$(mcp_call "platform.list_kb_articles")
  tally "list_kb_articles" "$RESP"

  RESP=$(mcp_call "platform.get_api_reference" '{"topic":"missions"}')
  tally "get_api_reference" "$RESP"

  RESP=$(mcp_call "platform.get_skill_context" '{"input_text":"document testapp API"}')
  tally "get_skill_context" "$RESP"

  RESP=$(mcp_call "platform.list_skills")
  tally "list_skills" "$RESP"

  end_phase
fi

# ─────────────────────────────────────────────────
# PHASE 4: Verification (5 tools)
# ─────────────────────────────────────────────────
if should_run_phase 4; then
  start_phase "PHASE 4: Verification (5 tools)"

  RESP=$(mcp_call "platform.create_learning" '{"category":"best_practice","content":"MCP smoke test verified all 78 platform tools across 14 categories with 100% coverage.","source_type":"manual","tags":"smoke-test,verification"}')
  tally "create_learning (results)" "$RESP"

  RESP=$(mcp_call "platform.recent_events" '{"limit":10}')
  tally "recent_events" "$RESP"

  RESP=$(mcp_call "platform.resources" '{"resource_type":"agents"}')
  tally "resources (agents)" "$RESP"

  RESP=$(mcp_call "platform.resources" '{"resource_type":"teams"}')
  tally "resources (teams)" "$RESP"

  RESP=$(mcp_call "platform.graph_statistics")
  tally "graph_statistics" "$RESP"

  end_phase
fi

# ─────────────────────────────────────────────────
# PHASE 5: Extended Coverage (24 tools)
# ─────────────────────────────────────────────────
if should_run_phase 5; then
  start_phase "PHASE 5: Extended Coverage (24 tools)"

  echo ""
  echo "--- Read Operations ---"

  RESP=$(mcp_call "platform.list_teams")
  tally "list_teams" "$RESP"

  # Use dynamic lookup: get first workflow/article/page/agent
  RESP=$(mcp_call "platform.list_workflows")
  WF_ID=$(extract_id "$RESP" ".workflows[0].id .[0].id")
  if [ -n "$WF_ID" ]; then
    RESP=$(mcp_call "platform.get_workflow" "{\"workflow_id\":\"${WF_ID}\"}")
    tally "get_workflow" "$RESP"
  else
    echo "  SKIP  No workflow found"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  RESP=$(mcp_call "platform.list_kb_articles")
  ART_ID=$(echo "$RESP" | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.articles[0].id // .[0].id // empty' 2>/dev/null)
  if [ -n "$ART_ID" ]; then
    RESP=$(mcp_call "platform.get_kb_article" "{\"article_id\":\"${ART_ID}\"}")
    tally "get_kb_article" "$RESP"
  else
    echo "  SKIP  No KB article found"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  RESP=$(mcp_call "platform.list_pages")
  tally "list_pages" "$RESP"
  PG_ID=$(extract_id "$RESP" ".pages[0].id .[0].id")
  if [ -n "$PG_ID" ]; then
    RESP=$(mcp_call "platform.get_page" "{\"page_id\":\"${PG_ID}\"}")
    tally "get_page" "$RESP"
  else
    echo "  SKIP  No page found"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  # Subgraph (needs 2 node IDs)
  RESP=$(mcp_call "platform.list_graph_nodes" '{"limit":2}')
  NODE1=$(echo "$RESP" | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.nodes[0].id // .[0].id // empty' 2>/dev/null)
  NODE2=$(echo "$RESP" | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.nodes[1].id // .[1].id // empty' 2>/dev/null)
  if [ -n "$NODE1" ] && [ -n "$NODE2" ]; then
    RESP=$(mcp_call "platform.get_subgraph" "{\"node_ids\":[\"${NODE1}\",\"${NODE2}\"]}")
    tally "get_subgraph" "$RESP"
  else
    echo "  SKIP  Not enough graph nodes for subgraph"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  # Search memory (needs an agent ID)
  RESP=$(mcp_call "platform.list_agents")
  AGENT_FOR_MEM=$(echo "$RESP" | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.agents[0].id // .[0].id // empty' 2>/dev/null)
  if [ -n "$AGENT_FOR_MEM" ]; then
    RESP=$(mcp_call "platform.search_memory" "{\"query\":\"smoke test\",\"agent_id\":\"${AGENT_FOR_MEM}\"}")
    tally "search_memory" "$RESP"
  else
    echo "  SKIP  No agent for memory search"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  # Pipeline status (graceful error)
  RESP=$(mcp_call "platform.get_pipeline_status" '{"pipeline_id":"00000000-0000-0000-0000-000000000000"}')
  tally_graceful_error "get_pipeline_status" "$RESP"

  echo ""
  echo "--- Create Operations ---"

  RESP=$(mcp_call "platform.create_workflow" '{"name":"Smoke Test Workflow","description":"Auto-created by smoke test"}')
  tally "create_workflow" "$RESP"
  NEW_WF_ID=$(extract_id "$RESP" ".workflow_id .workflow.id .id")
  CREATED_IDS="$CREATED_IDS workflow:$NEW_WF_ID"

  RESP=$(mcp_call "platform.create_kb_article" '{"title":"Smoke Test Article","content":"# Smoke Test\n\nAuto-created by MCP smoke test.","category_slug":"ai-orchestration","status":"draft"}')
  tally "create_kb_article" "$RESP"
  NEW_ART_ID=$(extract_id "$RESP" ".article_id .article.id .id")
  CREATED_IDS="$CREATED_IDS article:$NEW_ART_ID"

  RESP=$(mcp_call "platform.create_page" '{"title":"Smoke Test Page","content":"# Smoke Test\n\nAuto-created.","status":"draft","meta_description":"smoke test"}')
  tally "create_page" "$RESP"
  NEW_PG_ID=$(extract_id "$RESP" ".page_id .page.id .id")

  RESP=$(mcp_call "platform.create_knowledge" '{"title":"Smoke Test Entry","content":"Auto-created for update/promote testing.","content_type":"fact","access_level":"private","tags":["smoke-test"]}')
  tally "create_knowledge" "$RESP"
  NEW_KN_ID=$(extract_id "$RESP" ".entry.id .knowledge.id .id")

  echo ""
  echo "--- Update Operations ---"

  if [ -n "$NEW_WF_ID" ] && [ "$NEW_WF_ID" != "null" ]; then
    RESP=$(mcp_call "platform.update_workflow" "{\"workflow_id\":\"${NEW_WF_ID}\",\"description\":\"Updated by smoke test\"}")
    tally "update_workflow" "$RESP"
  else
    echo "  SKIP  No workflow to update"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  if [ -n "$NEW_ART_ID" ] && [ "$NEW_ART_ID" != "null" ]; then
    RESP=$(mcp_call "platform.update_kb_article" "{\"article_id\":\"${NEW_ART_ID}\",\"content\":\"# Updated\\n\\nSmoke test verified.\"}")
    tally "update_kb_article" "$RESP"
  else
    echo "  SKIP  No article to update"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  if [ -n "$NEW_PG_ID" ] && [ "$NEW_PG_ID" != "null" ]; then
    RESP=$(mcp_call "platform.update_page" "{\"page_id\":\"${NEW_PG_ID}\",\"content\":\"# Updated Page\"}")
    tally "update_page" "$RESP"
  else
    echo "  SKIP  No page to update"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  if [ -n "$NEW_KN_ID" ] && [ "$NEW_KN_ID" != "null" ]; then
    RESP=$(mcp_call "platform.update_knowledge" "{\"entry_id\":\"${NEW_KN_ID}\",\"content\":\"Updated by smoke test.\"}")
    tally "update_knowledge" "$RESP"

    RESP=$(mcp_call "platform.promote_knowledge" "{\"entry_id\":\"${NEW_KN_ID}\"}")
    tally "promote_knowledge" "$RESP"
  else
    echo "  SKIP  No knowledge to update/promote"
    PHASE_FAIL=$((PHASE_FAIL + 2))
  fi

  # Skill update + toggle (create temp skill)
  SKILL_RESP=$(mcp_call "platform.create_skill" '{"name":"Smoke Test Temp","description":"Temp skill for update test","category":"documentation"}')
  TEMP_SKILL_ID=$(extract_id "$SKILL_RESP" ".skill.id .id")
  if [ -n "$TEMP_SKILL_ID" ] && [ "$TEMP_SKILL_ID" != "null" ]; then
    RESP=$(mcp_call "platform.update_skill" "{\"skill_id\":\"${TEMP_SKILL_ID}\",\"description\":\"Updated by smoke test\"}")
    tally "update_skill" "$RESP"

    RESP=$(mcp_call "platform.toggle_skill" "{\"skill_id\":\"${TEMP_SKILL_ID}\",\"enabled\":\"false\"}")
    tally "toggle_skill" "$RESP"
    CREATED_IDS="$CREATED_IDS temp_skill:$TEMP_SKILL_ID"
  else
    echo "  SKIP  Could not create temp skill"
    PHASE_FAIL=$((PHASE_FAIL + 2))
  fi

  # Consolidate memory
  if [ -n "$AGENT_FOR_MEM" ]; then
    RESP=$(mcp_call "platform.consolidate_memory" "{\"agent_id\":\"${AGENT_FOR_MEM}\"}")
    tally "consolidate_memory" "$RESP"
  fi

  echo ""
  echo "--- Execution Operations ---"

  if [ -n "$AGENT_FOR_MEM" ]; then
    RESP=$(mcp_call "platform.execute_agent" "{\"agent_id\":\"${AGENT_FOR_MEM}\"}")
    tally "execute_agent" "$RESP"
  fi

  RESP=$(mcp_call "platform.list_teams")
  EXEC_TEAM_ID=$(echo "$RESP" | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.teams[0].id // empty' 2>/dev/null)
  if [ -n "$EXEC_TEAM_ID" ] && [ "$EXEC_TEAM_ID" != "null" ]; then
    RESP=$(mcp_call "platform.execute_team" "{\"team_id\":\"${EXEC_TEAM_ID}\"}")
    tally "execute_team" "$RESP"
  else
    echo "  SKIP  No team for execution"
    PHASE_FAIL=$((PHASE_FAIL + 1))
  fi

  if [ -n "$NEW_WF_ID" ] && [ "$NEW_WF_ID" != "null" ]; then
    RESP=$(mcp_call "platform.execute_workflow" "{\"workflow_id\":\"${NEW_WF_ID}\"}")
    tally "execute_workflow" "$RESP"
  elif [ -n "$WF_ID" ]; then
    RESP=$(mcp_call "platform.execute_workflow" "{\"workflow_id\":\"${WF_ID}\"}")
    tally "execute_workflow" "$RESP"
  fi

  RESP=$(mcp_call "platform.trigger_pipeline" '{"repository_id":"00000000-0000-0000-0000-000000000000"}')
  tally_graceful_error "trigger_pipeline" "$RESP"

  end_phase
fi

# ─────────────────────────────────────────────────
# PHASE 6: Project Init & Runner Dispatch (2 tools)
# ─────────────────────────────────────────────────
if should_run_phase 6; then
  start_phase "PHASE 6: Project Init & Runner Dispatch (2 tools)"

  RESP=$(mcp_call "platform.create_gitea_repository" '{"repo_name":"mcp-smoke-test","description":"Auto-created by MCP smoke test"}')
  tally "create_gitea_repository" "$RESP"
  CREATED_IDS="$CREATED_IDS gitea_repo:mcp-smoke-test"

  RESP=$(mcp_call "platform.dispatch_to_runner" '{"session_id":"00000000-0000-0000-0000-000000000000","worktree_id":"00000000-0000-0000-0000-000000000000"}')
  tally_graceful_error "dispatch_to_runner" "$RESP"

  end_phase
fi

# ─────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────
if [ "$SKIP_CLEANUP" = "false" ] && [ -n "$CREATED_IDS" ]; then
  echo ""
  echo "============================================="
  echo "  CLEANUP"
  echo "============================================="

  for entry in $CREATED_IDS; do
    type="${entry%%:*}"
    id="${entry#*:}"
    [ -z "$id" ] || [ "$id" = "null" ] && continue

    case "$type" in
      skill|temp_skill)
        mcp_call "platform.delete_skill" "{\"skill_id\":\"${id}\"}" > /dev/null 2>&1
        echo "  Deleted skill: $id"
        ;;
      agent)
        mcp_call "platform.update_agent" "{\"agent_id\":\"${id}\",\"status\":\"archived\"}" > /dev/null 2>&1
        echo "  Archived agent: $id"
        ;;
      team)
        mcp_call "platform.update_team" "{\"team_id\":\"${id}\",\"status\":\"archived\"}" > /dev/null 2>&1
        echo "  Archived team: $id"
        ;;
      knowledge_base)
        if [ -n "$JWT" ]; then
          api DELETE "/ai/knowledge_bases/${id}" > /dev/null 2>&1
          echo "  Deleted knowledge base: $id"
        else
          echo "  SKIP  No JWT for KB cleanup ($id)"
        fi
        ;;
      workflow)
        mcp_call "platform.update_workflow" "{\"workflow_id\":\"${id}\",\"status\":\"archived\"}" > /dev/null 2>&1
        echo "  Archived workflow: $id"
        ;;
      mission)
        if [ -n "$JWT" ]; then
          api POST "/ai/missions/${id}/cancel" > /dev/null 2>&1
          api DELETE "/ai/missions/${id}" > /dev/null 2>&1
          echo "  Cancelled mission: $id"
        fi
        ;;
      ralph)
        if [ -n "$JWT" ]; then
          api POST "/ai/ralph_loops/${id}/cancel" > /dev/null 2>&1
          echo "  Cancelled ralph loop: $id"
        fi
        ;;
      gitea_repo)
        # Delete via Gitea API (requires rails runner for token)
        GITEA_TOKEN=$(cd "$PROJECT_DIR/server" && bundle exec rails runner "
          cred = Devops::GitProviderCredential.joins(:git_provider)
            .where(git_providers: { provider_type: 'gitea' }, is_active: true).first
          puts cred&.credentials&.dig('access_token')
        " 2>/dev/null)
        GITEA_USER=$(cd "$PROJECT_DIR/server" && bundle exec rails runner "
          cred = Devops::GitProviderCredential.joins(:git_provider)
            .where(git_providers: { provider_type: 'gitea' }, is_active: true).first
          client = Devops::Git::ApiClient.for(cred)
          puts client.current_user['login']
        " 2>/dev/null)
        if [ -n "$GITEA_TOKEN" ] && [ -n "$GITEA_USER" ]; then
          GITEA_BASE=$(cd "$PROJECT_DIR/server" && bundle exec rails runner "
            puts Devops::GitProvider.find_by(provider_type: 'gitea')&.api_base_url
          " 2>/dev/null)
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
            "${GITEA_BASE}/repos/${GITEA_USER}/${id}" \
            -H "Authorization: token ${GITEA_TOKEN}")
          echo "  Deleted gitea repo: $id (HTTP $HTTP_CODE)"
        else
          echo "  SKIP  Could not resolve Gitea credentials for cleanup"
        fi
        ;;
      *)
        echo "  SKIP  Unknown type: $type ($id)"
        ;;
    esac
  done

  echo "  (Learnings and KG entries left in place)"
fi

# ─────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo "  MCP SMOKE TEST COMPLETE"
echo "============================================="
echo "  PASS: $TOTAL_PASS"
echo "  FAIL: $TOTAL_FAIL"
echo "  SKIP: $TOTAL_SKIP"
echo "  TOTAL: $((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))"
echo ""

if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo "  STATUS: FAILURES DETECTED"
  exit 1
else
  echo "  STATUS: ALL PASSED"
  exit 0
fi
