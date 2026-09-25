/**
 * The read permission behind each AI → Knowledge tab, matching what that tab's
 * endpoints enforce (ContextsController, TieredMemoryController, RagController,
 * KnowledgeGraphController, LearningController). KnowledgePage gates its tabs
 * on these; the navigation config opens Knowledge on any of them. It lives in
 * shared so the navigation config does not depend on the page.
 */
export const KNOWLEDGE_TAB_PERMISSIONS = {
  contexts: 'ai.context.read',
  memory: 'ai.memory.read',
  rag: 'ai.rag.read',
  graph: 'ai.knowledge_graph.read',
  learning: 'ai.analytics.read',
} as const;

export const KNOWLEDGE_PERMISSIONS: string[] = Object.values(KNOWLEDGE_TAB_PERMISSIONS);
