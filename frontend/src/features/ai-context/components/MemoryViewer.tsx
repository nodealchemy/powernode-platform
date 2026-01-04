import { useState, useEffect } from 'react';
import { contextApi } from '../services/contextApi';
import type { AiContextEntrySummary, AiContextEntry, EntryType, AiAgentSummary } from '../types';

interface MemoryViewerProps {
  agentId: string;
  onEntrySelect?: (entry: AiContextEntry) => void;
  onAddEntry?: () => void;
}

export function MemoryViewer({ agentId, onEntrySelect, onAddEntry }: MemoryViewerProps) {
  const [memories, setMemories] = useState<AiContextEntrySummary[]>([]);
  const [agent, setAgent] = useState<AiAgentSummary | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedType, setSelectedType] = useState<EntryType | ''>('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [expandedEntry, setExpandedEntry] = useState<AiContextEntry | null>(null);
  const [contextId, setContextId] = useState<string | null>(null);

  useEffect(() => {
    loadMemories();
  }, [agentId, selectedType]);

  const loadMemories = async () => {
    setIsLoading(true);
    const response = await contextApi.getAgentMemory(agentId, 1, 100, {
      entry_type: selectedType || undefined,
    });
    if (response.success && response.data) {
      setMemories(response.data.memories);
      setAgent(response.data.agent);
      setContextId(response.data.context.id);
    }
    setIsLoading(false);
  };

  const handleExpand = async (entry: AiContextEntrySummary) => {
    if (expandedId === entry.id) {
      setExpandedId(null);
      setExpandedEntry(null);
      return;
    }

    setExpandedId(entry.id);
    if (contextId) {
      const response = await contextApi.getEntry(contextId, entry.id);
      if (response.success && response.data) {
        setExpandedEntry(response.data.entry);
      }
    }
  };

  const entryTypes: { value: EntryType | ''; label: string }[] = [
    { value: '', label: 'All Types' },
    { value: 'fact', label: 'Facts' },
    { value: 'preference', label: 'Preferences' },
    { value: 'interaction', label: 'Interactions' },
    { value: 'knowledge', label: 'Knowledge' },
    { value: 'skill', label: 'Skills' },
    { value: 'relationship', label: 'Relationships' },
    { value: 'goal', label: 'Goals' },
    { value: 'constraint', label: 'Constraints' },
  ];

  // Group memories by type
  const groupedMemories = memories.reduce(
    (acc, memory) => {
      if (!acc[memory.entry_type]) {
        acc[memory.entry_type] = [];
      }
      acc[memory.entry_type].push(memory);
      return acc;
    },
    {} as Record<EntryType, AiContextEntrySummary[]>
  );

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          {agent && (
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-theme-primary bg-opacity-10 flex items-center justify-center">
                <span className="text-xl">🤖</span>
              </div>
              <div>
                <h3 className="font-medium text-theme-primary">{agent.name}</h3>
                <p className="text-sm text-theme-secondary">
                  {memories.length} memories stored
                </p>
              </div>
            </div>
          )}
        </div>
        <div className="flex items-center gap-3">
          <select
            value={selectedType}
            onChange={(e) => setSelectedType(e.target.value as EntryType | '')}
            className="px-4 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            {entryTypes.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
            ))}
          </select>
          {onAddEntry && (
            <button
              onClick={onAddEntry}
              className="px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
            >
              Add Memory
            </button>
          )}
        </div>
      </div>

      {/* Memory List */}
      {memories.length === 0 ? (
        <div className="text-center py-12 bg-theme-card border border-theme rounded-lg">
          <div className="text-4xl mb-4">🧠</div>
          <h3 className="text-lg font-medium text-theme-primary">No memories yet</h3>
          <p className="text-theme-secondary mt-1">
            This agent hasn't stored any memories
          </p>
          {onAddEntry && (
            <button
              onClick={onAddEntry}
              className="mt-4 px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
            >
              Add First Memory
            </button>
          )}
        </div>
      ) : selectedType ? (
        // Flat list when filtered
        <div className="space-y-2">
          {memories.map((memory) => (
            <MemoryItem
              key={memory.id}
              memory={memory}
              isExpanded={expandedId === memory.id}
              expandedEntry={expandedId === memory.id ? expandedEntry : null}
              onExpand={() => handleExpand(memory)}
              onSelect={onEntrySelect}
              contextId={contextId}
            />
          ))}
        </div>
      ) : (
        // Grouped by type
        <div className="space-y-6">
          {Object.entries(groupedMemories).map(([type, entries]) => (
            <div key={type}>
              <h4 className="text-sm font-medium text-theme-secondary mb-2 flex items-center gap-2">
                <span
                  className={`w-2 h-2 rounded-full ${contextApi.getEntryTypeColor(type as EntryType).split(' ')[0]}`}
                />
                {contextApi.getEntryTypeLabel(type as EntryType)}
                <span className="text-theme-tertiary">({entries.length})</span>
              </h4>
              <div className="space-y-2">
                {entries.map((memory) => (
                  <MemoryItem
                    key={memory.id}
                    memory={memory}
                    isExpanded={expandedId === memory.id}
                    expandedEntry={expandedId === memory.id ? expandedEntry : null}
                    onExpand={() => handleExpand(memory)}
                    onSelect={onEntrySelect}
                    contextId={contextId}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

interface MemoryItemProps {
  memory: AiContextEntrySummary;
  isExpanded: boolean;
  expandedEntry: AiContextEntry | null;
  onExpand: () => void;
  onSelect?: (entry: AiContextEntry) => void;
  contextId: string | null;
}

function MemoryItem({
  memory,
  isExpanded,
  expandedEntry,
  onExpand,
  onSelect,
}: MemoryItemProps) {
  return (
    <div className="bg-theme-card border border-theme rounded-lg overflow-hidden">
      <button
        onClick={onExpand}
        className="w-full p-4 text-left hover:bg-theme-surface transition-colors"
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <span
                className={`px-2 py-0.5 text-xs rounded ${contextApi.getEntryTypeColor(memory.entry_type)}`}
              >
                {contextApi.getEntryTypeLabel(memory.entry_type)}
              </span>
              <span className="font-mono text-sm text-theme-primary truncate">
                {memory.key}
              </span>
            </div>
            {memory.content_text && (
              <p className="text-sm text-theme-secondary mt-1 line-clamp-2">
                {memory.content_text}
              </p>
            )}
            <div className="flex items-center gap-4 mt-2 text-xs text-theme-tertiary">
              <span className={contextApi.getImportanceColor(memory.importance_score)}>
                {contextApi.formatImportanceScore(memory.importance_score)} importance
              </span>
              <span>{memory.access_count} accesses</span>
              <span>{new Date(memory.created_at).toLocaleDateString()}</span>
            </div>
          </div>
          <span className="text-theme-tertiary">{isExpanded ? '▼' : '▶'}</span>
        </div>
      </button>

      {isExpanded && expandedEntry && (
        <div className="p-4 border-t border-theme bg-theme-surface">
          <div className="space-y-4">
            {/* Tags */}
            {expandedEntry.tags.length > 0 && (
              <div className="flex flex-wrap gap-1">
                {expandedEntry.tags.map((tag) => (
                  <span
                    key={tag}
                    className="px-2 py-0.5 text-xs bg-theme-card text-theme-secondary rounded"
                  >
                    {tag}
                  </span>
                ))}
              </div>
            )}

            {/* Content */}
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Content</p>
              <pre className="p-3 bg-theme-card rounded text-sm text-theme-secondary overflow-x-auto">
                {JSON.stringify(expandedEntry.content, null, 2)}
              </pre>
            </div>

            {/* Metadata */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <p className="text-xs text-theme-tertiary">Source</p>
                <p className="text-theme-primary">{expandedEntry.source || 'Unknown'}</p>
              </div>
              <div>
                <p className="text-xs text-theme-tertiary">Confidence</p>
                <p className="text-theme-primary">
                  {(expandedEntry.confidence_score * 100).toFixed(0)}%
                </p>
              </div>
              <div>
                <p className="text-xs text-theme-tertiary">Has Embedding</p>
                <p className="text-theme-primary">
                  {expandedEntry.embedding ? 'Yes' : 'No'}
                </p>
              </div>
              <div>
                <p className="text-xs text-theme-tertiary">Last Accessed</p>
                <p className="text-theme-primary">
                  {expandedEntry.last_accessed_at
                    ? new Date(expandedEntry.last_accessed_at).toLocaleDateString()
                    : 'Never'}
                </p>
              </div>
            </div>

            {/* Actions */}
            {onSelect && (
              <div className="flex justify-end">
                <button
                  onClick={() => onSelect(expandedEntry)}
                  className="px-4 py-2 text-sm text-theme-primary hover:bg-theme-card rounded transition-colors"
                >
                  Edit Entry
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
