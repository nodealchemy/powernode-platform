export type MemoryTier = 'working' | 'short_term' | 'long_term' | 'shared';

export interface MemoryEntry {
  id?: string;
  key: string;
  value: unknown;
  tier: MemoryTier;
  session_id?: string;
  memory_type?: string;
  access_count?: number;
  expires_at?: string;
  created_at?: string;
}

export interface SharedKnowledgeEntry {
  id: string;
  title: string;
  content: string;
  content_type: string;
  access_level: string;
  tags: string[];
  quality_score?: number;
  usage_count: number;
  source_type: string;
  has_embedding: boolean;
  created_at: string;
}

export interface MemoryStats {
  working: { count: number };
  short_term: { total: number; active: number; expired: number };
  long_term: { total: number; active: number };
  shared: { total: number; with_embedding: number };
}

export interface SemanticSearchResult {
  tier: string;
  id: string;
  content: string;
  title?: string;
  category?: string;
  score: number;
  distance: number;
}
