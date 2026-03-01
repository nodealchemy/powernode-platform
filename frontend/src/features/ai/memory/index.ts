// Pages
export { KnowledgeMemoryPage, KnowledgeMemoryContent } from './pages/KnowledgeMemoryPage';
export { MemoryExplorerPage, MemoryExplorerContent } from './pages/MemoryExplorerPage';

// Content components (tab content for embedding in parent pages)
export { AgentMemoryContent } from './components/AgentMemoryContent';

// Memory tier components
export { MemoryStatsBar } from './components/MemoryStatsBar';
export { MemoryTierTabs } from './components/MemoryTierTabs';
export { MemoryEntryCard } from './components/MemoryEntryCard';
export { SharedKnowledgeList } from './components/SharedKnowledgeList';

// Context components (consolidated from context/)
export { ContextBrowser } from './components/ContextBrowser';
export { EntryEditor } from './components/EntryEditor';
export { MemoryViewer } from './components/MemoryViewer';
export { SearchResults } from './components/SearchResults';
export { ImportExportModal } from './components/ImportExportModal';

// Agent memory components (consolidated from agent-memory/)
export { MemoryTimeline } from './components/MemoryTimeline';
export { MemoryStats as AgentMemoryStats } from './components/AgentMemoryStats';
export { ContextInjectionPreview } from './components/ContextInjectionPreview';
export { MemoryEntryCard as AgentMemoryEntryCard } from './components/AgentMemoryEntryCard';
export { SharedLearningsPanel } from './components/SharedLearningsPanel';

// API services
export { contextApi } from './api/contextApi';

// Hooks
export { useContexts, useContext, useEntries, useEntry } from './hooks/useContext';
export { useAgentMemory } from './hooks/useAgentMemory';

// Types - Memory
export type {
  MemoryTier,
  MemoryEntry,
  SharedKnowledgeEntry,
  MemoryStats,
  SemanticSearchResult,
} from './types/memory';

// Types - Context
export type {
  ContextType,
  ContextScope,
  EntryType,
  AiPersistentContext,
  AiPersistentContextSummary,
  AiContextEntry,
  AiContextEntrySummary,
  AiAgentSummary,
  ContextFormData,
  EntryFormData,
  SearchResult,
  SearchParams,
} from './types/context';
