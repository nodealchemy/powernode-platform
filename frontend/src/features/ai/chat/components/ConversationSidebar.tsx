import React, { useState, useCallback, useRef, useEffect } from 'react';
import { Plus, PanelLeftClose, PanelLeft, Loader2, CheckSquare, X, Archive, Trash2, Pin, Tag } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { ConversationSearch } from './ConversationSearch';
import { ConversationListItem } from './ConversationListItem';
import type { ConversationBase } from '@/shared/services/ai/ConversationsApiService';
import { MessageSquare } from 'lucide-react';

const STORAGE_KEY = 'chat-sidebar-width';
const COLLAPSED_KEY = 'chat-sidebar-collapsed';
const MIN_WIDTH = 200;
const MAX_WIDTH = 400;
const DEFAULT_WIDTH = 280;
const COLLAPSED_WIDTH = 60;

type StatusFilter = 'all' | 'active' | 'archived';
type SearchMode = 'title' | 'messages';
type SortOption = 'last_activity' | 'created_at' | 'message_count';

interface ConversationSidebarProps {
  conversations: ConversationBase[];
  activeConversationId: string | null;
  loading: boolean;
  onSelectConversation: (id: string) => void;
  onNewChat: () => void;
  onArchive: (id: string) => void;
  onDelete: (id: string) => void;
  onPin: (id: string) => void;
  onUnpin: (id: string) => void;
  onSearch: (query: string) => void;
  onFilterChange: (status: StatusFilter) => void;
  activeFilter: StatusFilter;
  onBulkAction?: (ids: string[], action: string, params?: Record<string, unknown>) => void;
  onAddTag?: (id: string, tag: string) => void;
  onRemoveTag?: (id: string, tag: string) => void;
  onSearchMessages?: (query: string) => void;
  sortBy?: SortOption;
  onSortChange?: (sort: SortOption) => void;
  searchMode?: SearchMode;
  onSearchModeChange?: (mode: SearchMode) => void;
}

export const ConversationSidebar: React.FC<ConversationSidebarProps> = ({
  conversations,
  activeConversationId,
  loading,
  onSelectConversation,
  onNewChat,
  onArchive,
  onDelete,
  onPin,
  onUnpin,
  onSearch,
  onFilterChange,
  activeFilter,
  onBulkAction,
  onAddTag,
  onRemoveTag,
  onSearchMessages,
  sortBy,
  onSortChange,
  searchMode,
  onSearchModeChange,
}) => {
  const [width, setWidth] = useState(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved ? Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, parseInt(saved, 10))) : DEFAULT_WIDTH;
  });

  const [collapsed, setCollapsed] = useState(() => {
    return localStorage.getItem(COLLAPSED_KEY) === 'true';
  });

  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkTagInput, setBulkTagInput] = useState(false);
  const [bulkTagValue, setBulkTagValue] = useState('');
  const bulkTagRef = useRef<HTMLInputElement>(null);

  const isDragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    isDragging.current = true;
    startX.current = e.clientX;
    startWidth.current = width;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [width]);

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDragging.current) return;
      const delta = e.clientX - startX.current;
      const newWidth = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, startWidth.current + delta));
      setWidth(newWidth);
      localStorage.setItem(STORAGE_KEY, String(newWidth));
    };

    const handleMouseUp = () => {
      isDragging.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, []);

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(COLLAPSED_KEY, String(next));
      return next;
    });
  }, []);

  const handleDoubleClickHandle = useCallback(() => {
    toggleCollapsed();
  }, [toggleCollapsed]);

  // Multi-select handlers
  const toggleSelectMode = useCallback(() => {
    setSelectMode(prev => {
      if (prev) {
        setSelectedIds(new Set());
        setBulkTagInput(false);
      }
      return !prev;
    });
  }, []);

  const handleSelect = useCallback((id: string, selected: boolean) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (selected) {
        next.add(id);
      } else {
        next.delete(id);
      }
      return next;
    });
  }, []);

  const handleBulkAction = useCallback((action: string) => {
    if (selectedIds.size === 0 || !onBulkAction) return;
    const ids = Array.from(selectedIds);
    onBulkAction(ids, action);
    setSelectedIds(new Set());
    setSelectMode(false);
  }, [selectedIds, onBulkAction]);

  const handleBulkTag = useCallback(() => {
    const trimmed = bulkTagValue.trim().toLowerCase();
    if (!trimmed || selectedIds.size === 0 || !onBulkAction) return;
    const ids = Array.from(selectedIds);
    onBulkAction(ids, 'tag', { tag: trimmed });
    setBulkTagValue('');
    setBulkTagInput(false);
    setSelectedIds(new Set());
    setSelectMode(false);
  }, [bulkTagValue, selectedIds, onBulkAction]);

  useEffect(() => {
    if (bulkTagInput && bulkTagRef.current) {
      bulkTagRef.current.focus();
    }
  }, [bulkTagInput]);

  // Handle search based on mode
  const handleSearch = useCallback((query: string) => {
    if (searchMode === 'messages' && onSearchMessages && query) {
      onSearchMessages(query);
    } else {
      onSearch(query);
    }
  }, [searchMode, onSearch, onSearchMessages]);

  const sidebarWidth = collapsed ? COLLAPSED_WIDTH : width;

  // Separate pinned and unpinned conversations
  const pinnedConversations = conversations.filter((c) => c.pinned);
  const unpinnedConversations = conversations.filter((c) => !c.pinned);

  const renderConversationItem = (conv: ConversationBase) => (
    <ConversationListItem
      key={conv.id}
      conversation={conv}
      isActive={activeConversationId === conv.id}
      onClick={() => onSelectConversation(conv.id)}
      onArchive={() => onArchive(conv.id)}
      onDelete={() => onDelete(conv.id)}
      onPin={() => onPin(conv.id)}
      onUnpin={() => onUnpin(conv.id)}
      onAddTag={onAddTag ? (tag) => onAddTag(conv.id, tag) : undefined}
      onRemoveTag={onRemoveTag ? (tag) => onRemoveTag(conv.id, tag) : undefined}
      selectable={selectMode}
      selected={selectedIds.has(conv.id)}
      onSelect={(selected) => handleSelect(conv.id, selected)}
    />
  );

  return (
    <div
      className="relative flex flex-col h-full bg-theme-surface border-r border-theme"
      style={{ width: sidebarWidth, minWidth: sidebarWidth }}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-3 border-b border-theme">
        {!collapsed && (
          <h3 className="text-sm font-semibold text-theme-primary truncate">
            Conversations
          </h3>
        )}
        <div className="flex items-center gap-1">
          {!collapsed && (
            <>
              <Button
                variant="primary"
                size="xs"
                onClick={onNewChat}
                title="New chat"
              >
                <Plus className="h-3.5 w-3.5 mr-1" />
                New
              </Button>
              {onBulkAction && (
                <Button
                  variant={selectMode ? 'secondary' : 'ghost'}
                  size="xs"
                  iconOnly
                  onClick={toggleSelectMode}
                  title={selectMode ? 'Cancel selection' : 'Select multiple'}
                >
                  <CheckSquare className="h-3.5 w-3.5" />
                </Button>
              )}
            </>
          )}
          <Button
            variant="ghost"
            size="xs"
            iconOnly
            onClick={toggleCollapsed}
            title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            {collapsed ? <PanelLeft className="h-4 w-4" /> : <PanelLeftClose className="h-4 w-4" />}
          </Button>
        </div>
      </div>

      {/* Collapsed: just icon buttons */}
      {collapsed ? (
        <div className="flex flex-col items-center gap-2 py-3">
          <Button
            variant="primary"
            size="xs"
            iconOnly
            onClick={onNewChat}
            title="New chat"
          >
            <Plus className="h-4 w-4" />
          </Button>
          {conversations.slice(0, 8).map((conv) => (
            <button
              key={conv.id}
              onClick={() => onSelectConversation(conv.id)}
              title={conv.title || 'Chat'}
              className={`w-9 h-9 rounded-md flex items-center justify-center transition-colors ${
                activeConversationId === conv.id
                  ? 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
                  : 'text-theme-secondary hover:bg-theme-surface-hover'
              }`}
            >
              <MessageSquare className="h-4 w-4" />
            </button>
          ))}
        </div>
      ) : (
        <>
          {/* Search, filters, and sort */}
          <ConversationSearch
            onSearch={handleSearch}
            onFilterChange={onFilterChange}
            activeFilter={activeFilter}
            searchMode={searchMode}
            onSearchModeChange={onSearchModeChange}
            sortBy={sortBy}
            onSortChange={onSortChange}
          />

          {/* Conversation list */}
          <div className="flex-1 overflow-y-auto">
            {loading && conversations.length === 0 ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-5 w-5 text-theme-text-tertiary animate-spin" />
              </div>
            ) : conversations.length === 0 ? (
              <EmptyState
                icon={MessageSquare}
                title="No conversations"
                description="Start a new chat to begin"
                action={
                  <Button variant="primary" size="sm" onClick={onNewChat}>
                    <Plus className="h-4 w-4 mr-1" />
                    New Chat
                  </Button>
                }
              />
            ) : (
              <>
                {/* Pinned section */}
                {pinnedConversations.length > 0 && (
                  <div>
                    <div className="px-3 py-1.5">
                      <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                        Pinned
                      </span>
                    </div>
                    {pinnedConversations.map(renderConversationItem)}
                  </div>
                )}

                {/* Unpinned / recent section */}
                {unpinnedConversations.length > 0 && (
                  <div>
                    {pinnedConversations.length > 0 && (
                      <div className="px-3 py-1.5 border-t border-theme">
                        <span className="text-[10px] font-semibold text-theme-text-tertiary uppercase tracking-wider">
                          Recent
                        </span>
                      </div>
                    )}
                    {unpinnedConversations.map(renderConversationItem)}
                  </div>
                )}
              </>
            )}
          </div>

          {/* Bulk action bar */}
          {selectMode && selectedIds.size > 0 && (
            <div className="border-t border-theme bg-theme-surface-secondary p-2">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs text-theme-secondary">
                  {selectedIds.size} selected
                </span>
                <button
                  onClick={() => {
                    setSelectedIds(new Set());
                    setSelectMode(false);
                  }}
                  className="text-theme-text-tertiary hover:text-theme-primary"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </div>

              {bulkTagInput ? (
                <div className="flex gap-1">
                  <input
                    ref={bulkTagRef}
                    type="text"
                    value={bulkTagValue}
                    onChange={(e) => setBulkTagValue(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') handleBulkTag();
                      if (e.key === 'Escape') setBulkTagInput(false);
                    }}
                    placeholder="Tag name..."
                    className="flex-1 px-2 py-1 text-xs bg-theme-background border border-theme rounded text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
                    maxLength={20}
                  />
                  <Button variant="primary" size="xs" onClick={handleBulkTag} disabled={!bulkTagValue.trim()}>
                    Add
                  </Button>
                </div>
              ) : (
                <div className="flex gap-1 flex-wrap">
                  <Button variant="ghost" size="xs" onClick={() => handleBulkAction('archive')} title="Archive all selected">
                    <Archive className="h-3 w-3 mr-1" />
                    Archive
                  </Button>
                  <Button variant="ghost" size="xs" onClick={() => handleBulkAction('pin')} title="Pin all selected">
                    <Pin className="h-3 w-3 mr-1" />
                    Pin
                  </Button>
                  <Button variant="ghost" size="xs" onClick={() => setBulkTagInput(true)} title="Tag all selected">
                    <Tag className="h-3 w-3 mr-1" />
                    Tag
                  </Button>
                  <Button
                    variant="ghost"
                    size="xs"
                    onClick={() => {
                      if (window.confirm(`Delete ${selectedIds.size} conversation${selectedIds.size > 1 ? 's' : ''}? This cannot be undone.`)) {
                        handleBulkAction('delete');
                      }
                    }}
                    title="Delete all selected"
                    className="text-theme-error hover:text-theme-error"
                  >
                    <Trash2 className="h-3 w-3 mr-1" />
                    Delete
                  </Button>
                </div>
              )}
            </div>
          )}
        </>
      )}

      {/* Drag handle */}
      {!collapsed && (
        <div
          onMouseDown={handleMouseDown}
          onDoubleClick={handleDoubleClickHandle}
          className="absolute top-0 right-0 w-1 h-full cursor-col-resize hover:bg-theme-interactive-primary/30 transition-colors"
        />
      )}
    </div>
  );
};
