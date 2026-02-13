import React, { useState, useRef, useEffect } from 'react';
import {
  MoreVertical,
  Pencil,
  Trash2,
  MessageSquareReply,
  Copy,
  Check,
  History,
  Undo2,
} from 'lucide-react';
import type { AiMessage } from '@/shared/types/ai';

interface MessageActionsProps {
  message: AiMessage;
  canEdit: boolean;
  canDelete: boolean;
  onEdit: () => void;
  onDelete: () => void;
  onReply: () => void;
  onViewThread?: () => void;
  onViewEditHistory?: () => void;
}

export const MessageActions: React.FC<MessageActionsProps> = ({
  message,
  canEdit,
  canDelete,
  onEdit,
  onDelete,
  onReply,
  onViewThread,
  onViewEditHistory,
}) => {
  const [showMenu, setShowMenu] = useState(false);
  const [copied, setCopied] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

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

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(message.content);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // clipboard not available
    }
    setShowMenu(false);
  };

  const hasThread = (message.reply_count ?? 0) > 0;

  return (
    <div ref={menuRef} className="relative">
      <button
        onClick={(e) => {
          e.stopPropagation();
          setShowMenu(!showMenu);
        }}
        className="p-1 rounded hover:bg-theme-surface-hover text-theme-text-tertiary transition-colors"
        title="Message actions"
      >
        <MoreVertical className="h-3.5 w-3.5" />
      </button>

      {showMenu && (
        <div className="absolute right-0 top-7 z-50 w-44 bg-theme-surface border border-theme rounded-md shadow-lg py-1">
          {/* Copy */}
          <button
            onClick={handleCopy}
            className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
          >
            {copied ? <Check className="h-3.5 w-3.5 text-theme-success" /> : <Copy className="h-3.5 w-3.5" />}
            {copied ? 'Copied!' : 'Copy message'}
          </button>

          {/* Reply */}
          <button
            onClick={() => {
              setShowMenu(false);
              onReply();
            }}
            className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
          >
            <MessageSquareReply className="h-3.5 w-3.5" />
            Reply in thread
          </button>

          {/* View thread */}
          {hasThread && onViewThread && (
            <button
              onClick={() => {
                setShowMenu(false);
                onViewThread();
              }}
              className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
            >
              <MessageSquareReply className="h-3.5 w-3.5" />
              View thread ({message.reply_count})
            </button>
          )}

          {/* Edit */}
          {canEdit && message.sender_type !== 'system' && (
            <button
              onClick={() => {
                setShowMenu(false);
                onEdit();
              }}
              className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
            >
              <Pencil className="h-3.5 w-3.5" />
              Edit message
            </button>
          )}

          {/* View edit history */}
          {message.is_edited && onViewEditHistory && (
            <button
              onClick={() => {
                setShowMenu(false);
                onViewEditHistory();
              }}
              className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-secondary hover:bg-theme-surface-hover"
            >
              <History className="h-3.5 w-3.5" />
              Edit history
            </button>
          )}

          {/* Divider before destructive actions */}
          {canDelete && <div className="border-t border-theme my-1" />}

          {/* Delete */}
          {canDelete && message.sender_type !== 'system' && (
            <button
              onClick={() => {
                setShowMenu(false);
                onDelete();
              }}
              className="flex items-center gap-2 w-full px-3 py-1.5 text-xs text-theme-error hover:bg-theme-error-background"
            >
              {message.deleted_at ? (
                <>
                  <Undo2 className="h-3.5 w-3.5" />
                  Restore message
                </>
              ) : (
                <>
                  <Trash2 className="h-3.5 w-3.5" />
                  Delete message
                </>
              )}
            </button>
          )}
        </div>
      )}
    </div>
  );
};
