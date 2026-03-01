import React, { useState, useRef, useEffect } from 'react';
import { Bot, MoreVertical, Archive, Trash2, MessageSquare, Pin, PinOff, Tag, X, Users } from 'lucide-react';
import { Avatar } from '@/shared/components/ui/Avatar';
import type { ConversationBase } from '@/shared/services/ai/ConversationsApiService';

interface ConversationListItemProps {
  conversation: ConversationBase;
  isActive: boolean;
  onClick: () => void;
  onArchive: () => void;
  onDelete: () => void;
  onPin: () => void;
  onUnpin: () => void;
  onAddTag?: (tag: string) => void;
  onRemoveTag?: (tag: string) => void;
  selectable?: boolean;
  selected?: boolean;
  onSelect?: (selected: boolean) => void;
}

function formatRelativeTime(dateStr: string | null): string {
  if (!dateStr) return '';
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
}

const TAG_COLORS = [
  'bg-theme-info/10 text-theme-info',
  'bg-theme-success/10 text-theme-success',
  'bg-theme-interactive-primary/10 text-theme-interactive-primary',
  'bg-theme-warning/10 text-theme-warning',
  'bg-theme-error/10 text-theme-error',
];

function getTagColor(tag: string): string {
  let hash = 0;
  for (let i = 0; i < tag.length; i++) {
    hash = tag.charCodeAt(i) + ((hash << 5) - hash);
  }
  return TAG_COLORS[Math.abs(hash) % TAG_COLORS.length];
}

export const ConversationListItem: React.FC<ConversationListItemProps> = ({
  conversation,
  isActive,
  onClick,
  onArchive,
  onDelete,
  onPin,
  onUnpin,
  onAddTag,
  onRemoveTag,
  selectable = false,
  selected = false,
  onSelect,
}) => {
  const [showMenu, setShowMenu] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [showTagInput, setShowTagInput] = useState(false);
  const [tagValue, setTagValue] = useState('');
  const menuRef = useRef<HTMLDivElement>(null);
  const tagInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setShowMenu(false);
      }
    };
    if (showMenu) {
      document.addEventListener('mousedown', handleClickOutside, true);
      return () => document.removeEventListener('mousedown', handleClickOutside, true);
    }
  }, [showMenu]);

  useEffect(() => {
    if (showTagInput && tagInputRef.current) {
      tagInputRef.current.focus();
    }
  }, [showTagInput]);

  const title = conversation.title || 'New Chat';
  const isTeamConversation = conversation.conversation_type === 'team';
  const agentName = isTeamConversation && conversation.agent_team?.name ? conversation.agent_team.name : (conversation.ai_agent?.name || 'Unknown Agent');
  const timeStr = formatRelativeTime(conversation.last_activity_at || conversation.created_at);
  const tags = conversation.tags || [];

  const handleAddTag = () => {
    const trimmed = tagValue.trim().toLowerCase();
    if (trimmed && onAddTag && !tags.includes(trimmed)) {
      onAddTag(trimmed);
    }
    setTagValue('');
    setShowTagInput(false);
  };

  const handleTagKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleAddTag();
    } else if (e.key === 'Escape') {
      setTagValue('');
      setShowTagInput(false);
    }
  };

  return (
    <div
      onClick={selectable ? undefined : onClick}
      className={`group relative flex items-start gap-2.5 px-3 py-2.5 cursor-pointer transition-colors ${
        isActive
          ? 'bg-theme-interactive-primary/10 border-l-2 border-theme-interactive-primary'
          : 'hover:bg-theme-surface-hover border-l-2 border-transparent'
      }`}
    >
      {/* Multi-select checkbox */}
      {selectable && (
        <div className="flex items-center pt-1">
          <input
            type="checkbox"
            checked={selected}
            onChange={(e) => {
              e.stopPropagation();
              onSelect?.(e.target.checked);
            }}
            onClick={(e) => e.stopPropagation()}
            className="h-3.5 w-3.5 rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
          />
        </div>
      )}

      <div onClick={selectable ? onClick : undefined} className="flex items-start gap-2.5 flex-1 min-w-0">
        <Avatar size="sm" fallback={agentName}>
          {isTeamConversation ? <Users className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
        </Avatar>

        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-1">
            <div className="flex items-center gap-1 min-w-0">
              {conversation.pinned && (
                <Pin className="h-3 w-3 text-theme-interactive-primary flex-shrink-0" />
              )}
              {isTeamConversation && (
                <span className="text-[9px] font-semibold uppercase px-1 py-0.5 rounded bg-theme-interactive-primary/10 text-theme-interactive-primary flex-shrink-0">
                  Team
                </span>
              )}
              <span className="text-sm font-medium text-theme-primary truncate">
                {title}
              </span>
            </div>
            <span className="text-[10px] text-theme-text-tertiary whitespace-nowrap flex-shrink-0">
              {timeStr}
            </span>
          </div>

          <div className="flex items-center justify-between gap-1 mt-0.5">
            <span className="text-xs text-theme-secondary truncate">
              {agentName}
            </span>
            {conversation.message_count > 0 && (
              <span className="flex items-center gap-0.5 text-[10px] text-theme-text-tertiary flex-shrink-0">
                <MessageSquare className="h-3 w-3" />
                {conversation.message_count}
              </span>
            )}
          </div>

          {/* Tags */}
          {tags.length > 0 && (
            <div className="flex items-center gap-1 mt-1 flex-wrap">
              {tags.map((tag) => (
                <span
                  key={tag}
                  className={`inline-flex items-center gap-0.5 text-[9px] px-1.5 py-0.5 rounded-full font-medium ${getTagColor(tag)}`}
                >
                  {tag}
                  {onRemoveTag && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onRemoveTag(tag);
                      }}
                      className="hover:opacity-70"
                    >
                      <X className="h-2.5 w-2.5" />
                    </button>
                  )}
                </span>
              ))}
            </div>
          )}

          {/* Inline tag input */}
          {showTagInput && (
            <div className="mt-1" onClick={(e) => e.stopPropagation()}>
              <input
                ref={tagInputRef}
                type="text"
                value={tagValue}
                onChange={(e) => setTagValue(e.target.value)}
                onKeyDown={handleTagKeyDown}
                onBlur={handleAddTag}
                placeholder="Tag name..."
                className="w-full px-1.5 py-0.5 text-[10px] bg-theme-background border border-theme rounded text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
                maxLength={20}
              />
            </div>
          )}
        </div>
      </div>

      {/* Action menu */}
      {!selectable && (
        <div ref={menuRef} className="relative flex-shrink-0">
          <button
            onClick={(e) => {
              e.stopPropagation();
              setShowMenu(!showMenu);
            }}
            className="p-0.5 rounded text-theme-text-tertiary hover:bg-theme-surface-hover hover:text-theme-secondary transition-colors"
          >
            <MoreVertical className="h-3.5 w-3.5 text-theme-text-tertiary" />
          </button>

          {showMenu && (
            <div className="absolute right-0 top-6 z-50 w-36 bg-theme-surface border border-theme rounded-md shadow-lg py-1">
              {conversation.pinned ? (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setShowMenu(false);
                    onUnpin();
                  }}
                  className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
                >
                  <PinOff className="h-3.5 w-3.5" />
                  Unpin
                </button>
              ) : (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setShowMenu(false);
                    onPin();
                  }}
                  className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
                >
                  <Pin className="h-3.5 w-3.5" />
                  Pin
                </button>
              )}
              {onAddTag && (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setShowMenu(false);
                    setShowTagInput(true);
                  }}
                  className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
                >
                  <Tag className="h-3.5 w-3.5" />
                  Add Tag
                </button>
              )}
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowMenu(false);
                  onArchive();
                }}
                className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
              >
                <Archive className="h-3.5 w-3.5" />
                Archive
              </button>
              {confirmDelete ? (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setShowMenu(false);
                    setConfirmDelete(false);
                    onDelete();
                  }}
                  className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-white bg-theme-danger hover:bg-theme-danger/90"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  Confirm Delete
                </button>
              ) : (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setConfirmDelete(true);
                  }}
                  className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-error hover:bg-theme-error-background"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  Delete
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
