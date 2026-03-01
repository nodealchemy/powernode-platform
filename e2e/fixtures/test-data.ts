/**
 * Test data fixtures for Playwright E2E tests
 *
 * Provides consistent test data across all AI functionality tests.
 */

/**
 * Test provider data
 */
export const TEST_PROVIDER = {
  name: 'Test Ollama Provider',
  type: 'ollama',
  baseUrl: 'http://localhost:11434',
  description: 'Local Ollama instance for testing',
};

/**
 * Test agent data
 */
export const TEST_AGENT = {
  name: 'E2E Test Agent',
  description: 'Agent created by Playwright E2E tests',
  systemPrompt: 'You are a helpful assistant for testing purposes. Keep responses brief.',
  model: 'llama3:8b',
  temperature: 0.7,
  maxTokens: 1000,
};

/**
 * Test conversation data
 */
export const TEST_CONVERSATION = {
  title: 'E2E Test Conversation',
  initialMessage: 'Hello, this is a test message from Playwright E2E tests.',
  followUpMessage: 'What is 2 + 2?',
  contextTestMessage: 'My name is Test User.',
  contextVerifyMessage: 'What is my name?',
};

/**
 * Test workflow data
 */
export const TEST_WORKFLOW = {
  name: 'E2E Test Workflow',
  description: 'Workflow created by Playwright E2E tests',
  nodes: {
    start: { type: 'start', position: { x: 100, y: 100 } },
    agent: { type: 'ai_agent', position: { x: 300, y: 100 } },
    end: { type: 'end', position: { x: 500, y: 100 } },
  },
};

/**
 * Test agent team data
 */
export const TEST_AGENT_TEAM = {
  name: 'E2E Test Team',
  description: 'Agent team created by Playwright E2E tests',
  type: 'sequential',
  memberCount: 2,
};

/**
 * Test context/memory data
 */
export const TEST_CONTEXT = {
  name: 'E2E Test Memory',
  type: 'agent_memory',
  entries: [
    { key: 'user_name', type: 'factual', value: { name: 'Test User' } },
    { key: 'preference', type: 'experiential', value: { content: 'User prefers concise responses' } },
  ],
};

/**
 * Test prompt template data
 */
export const TEST_PROMPT_TEMPLATE = {
  name: 'E2E Test Prompt',
  category: 'general',
  content: 'You are a {{role}} assistant. Help the user with {{task}}.',
  description: 'Prompt template created by Playwright E2E tests',
  variables: ['role', 'task'],
};

/**
 * Test agent card data
 */
export const TEST_AGENT_CARD = {
  name: 'E2E Test Agent Card',
  description: 'Agent card created by Playwright E2E tests',
  url: 'http://localhost:3000/a2a',
  skills: ['code_review', 'testing'],
};

/**
 * Test role profile data
 */
export const TEST_ROLE_PROFILE = {
  name: 'E2E Test Profile',
  role_type: 'worker',
  description: 'Role profile created by Playwright E2E tests',
};

/**
 * Test review config data
 */
export const TEST_REVIEW_CONFIG = {
  auto_review_enabled: true,
  review_mode: 'blocking' as const,
  review_task_types: ['execution'],
  max_revisions: 3,
  reviewer_role_type: 'reviewer',
  quality_threshold: 0.7,
};

/**
 * Test trajectory data
 */
export const TEST_TRAJECTORY = {
  title: 'E2E Test Trajectory',
  trajectory_type: 'task_completion',
  tags: ['e2e-test', 'automation'],
};

/**
 * Test Ralph Loop data
 */
export const TEST_RALPH_LOOP = {
  name: 'E2E Test Ralph Loop',
  description: 'Ralph loop created by Playwright E2E tests',
  default_agent_id: null as string | null,  // Set at runtime from available agents
  max_iterations: 10,
};

/**
 * Test Parallel Execution session data
 */
export const TEST_PARALLEL_SESSION = {
  repository_path: '/tmp/e2e-test-repo',
  base_branch: 'main',
  merge_strategy: 'sequential' as const,
  max_parallel: 4,
  branch_suffixes: 'feature-a, feature-b, feature-c',
};

/**
 * Unique ID generator for test data
 * Prevents collisions when running tests in parallel
 */
export function uniqueId(prefix: string = 'test'): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  return `${prefix}_${timestamp}_${random}`;
}

/**
 * Generate unique test data with ID suffix
 */
export function uniqueTestData<T extends { name: string }>(data: T): T {
  return {
    ...data,
    name: `${data.name} ${uniqueId()}`,
  };
}

/**
 * API endpoints for AI functionality
 */
export const API_ENDPOINTS = {
  providers: '/api/v1/ai/providers',
  agents: '/api/v1/ai/agents',
  conversations: '/api/v1/ai/conversations',
  workflows: '/api/v1/ai/workflows',
  agentTeams: '/api/v1/ai/agent-teams',
  contexts: '/api/v1/ai/contexts',
  monitoring: '/api/v1/ai/monitoring',
  analytics: '/api/v1/ai/analytics',
  roleProfiles: '/api/v1/ai/teams/role_profiles',
  trajectories: '/api/v1/ai/teams/trajectories',
  taskReviews: '/api/v1/ai/teams/reviews',
  ralphLoops: '/api/v1/ai/ralph_loops',
  worktreeSessions: '/api/v1/ai/worktree_sessions',
  agentContainers: '/api/v1/ai/agent_containers',
};

/**
 * Frontend routes for AI functionality
 */
export const ROUTES = {
  overview: '/app/ai',
  providers: '/app/ai/providers',
  agents: '/app/ai/agents',
  conversations: '/app/ai/conversations',
  workflows: '/app/ai/workflows',
  agentTeams: '/app/ai/agent-teams',
  contexts: '/app/ai/contexts',
  monitoring: '/app/ai/monitoring',
  analytics: '/app/ai/analytics',
  governance: '/app/ai/governance',
  sandbox: '/app/ai/sandbox',
  mcp: '/app/ai/mcp',
  prompts: '/app/ai/prompts',
  a2aTasks: '/app/ai/a2a-tasks',
  agentCards: '/app/ai/agent-cards',
  trajectories: '/app/ai/agent-teams/trajectories',
  ralphLoops: '/app/ai/ralph-loops',
  communityAgents: '/app/ai/community',
  containers: '/app/devops/containers',
  chatChannels: '/app/ai/chat-channels',
  marketplace: '/app/ai/agent-marketplace',
  publisher: '/app/ai/publisher',
  debug: '/app/ai/debug',
  devops: '/app/ai/devops-templates',
  devopsTemplates: '/app/ai/devops-templates',
  plugins: '/app/ai/plugins',
  parallelExecution: '/app/ai/parallel-execution',
  selfHealing: '/app/ai/self-healing',
  learningRecommendations: '/app/ai/learning/recommendations',
  learningInsights: '/app/ai/learning/insights',
  chatDetached: '/chat/detached',

  // Missions & Code Factory
  missions: '/app/ai/missions',
  missionsCodeFactory: '/app/ai/missions/code-factory',

  // Knowledge sub-tabs
  skills: '/app/ai/knowledge/skills',
  knowledgeGraph: '/app/ai/knowledge/graph',

  // AI consolidated routes
  infrastructure: '/app/ai/infrastructure',
  modelRouter: '/app/ai/infrastructure/model-router',
  memory: '/app/ai/memory',
  execution: '/app/ai/execution',
  knowledge: '/app/ai/knowledge',
  autonomy: '/app/ai/autonomy',
  sandboxes: '/app/ai/sandboxes',
  security: '/app/ai/security',
  audit: '/app/ai/audit',
  evaluation: '/app/ai/evaluation',
  aiBilling: '/app/ai/billing',
  workflowMonitoring: '/app/ai/workflows/monitoring',

  // DevOps routes
  devopsOverview: '/app/devops',
  gitProviders: '/app/devops/git',
  repositories: '/app/devops/repositories',
  pipelines: '/app/devops/pipelines',
  runners: '/app/devops/runners',
  webhooks: '/app/devops/webhooks',
  integrations: '/app/devops/integrations',
  apiKeys: '/app/devops/api-keys',
  dockerHosts: '/app/devops/docker',
  swarmClusters: '/app/devops/swarm',
};
