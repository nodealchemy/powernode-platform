import React, { useState, useCallback } from 'react';
import {
  Minimize2,
  Maximize2,
  ExternalLink,
  X,
  ArrowDownToLine,
  PanelLeft,
  PanelLeftClose,
  MoreVertical,
  Pin,
  PinOff,
  Archive,
  Trash2,
  Clock,
} from 'lucide-react';
import { useChatWindow } from '../context/ChatWindowContext';
import { ScheduledMessagesPanel } from './ScheduledMessagesPanel';
import { conversationsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ChatWindowHeaderProps {
  onPointerDown?: (e: React.PointerEvent) => void;
}

export const ChatWindowHeader: React.FC<ChatWindowHeaderProps> = ({ onPointerDown }) => {
  const { state, setMode, isDetachedMode, toggleSidebar } = useChatWindow();
  const { addNotification } = useNotifications();
  const [showActions, setShowActions] = useState(false);
  const [showSchedule, setShowSchedule] = useState(false);

  const activeTab = state.tabs.find(t => t.id === state.activeTabId);
  const isMaximized = state.mode === 'maximized';

  const handlePin = useCallback(async () => {
    if (!activeTab?.conversationId) return;
    try {
      await conversationsApi.pinConversation(activeTab.conversationId);
      addNotification({ type: 'success', message: 'Conversation pinned' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to pin conversation' });
    }
    setShowActions(false);
  }, [activeTab, addNotification]);

  const handleUnpin = useCallback(async () => {
    if (!activeTab?.conversationId) return;
    try {
      await conversationsApi.unpinConversation(activeTab.conversationId);
      addNotification({ type: 'success', message: 'Conversation unpinned' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to unpin conversation' });
    }
    setShowActions(false);
  }, [activeTab, addNotification]);

  const handleArchive = useCallback(async () => {
    if (!activeTab?.conversationId) return;
    try {
      await conversationsApi.archiveConversation(activeTab.conversationId);
      addNotification({ type: 'success', message: 'Conversation archived' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to archive conversation' });
    }
    setShowActions(false);
  }, [activeTab, addNotification]);

  const handleDelete = useCallback(async () => {
    if (!activeTab?.conversationId) return;
    if (!window.confirm('Delete this conversation? This cannot be undone.')) return;
    try {
      await conversationsApi.deleteConversation(activeTab.conversationId);
      addNotification({ type: 'success', message: 'Conversation deleted' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to delete conversation' });
    }
    setShowActions(false);
  }, [activeTab, addNotification]);

  return (
    <div
      className="flex items-center justify-between px-3 py-2 border-b border-theme bg-theme-surface select-none shrink-0"
      onPointerDown={onPointerDown}
      style={{ cursor: onPointerDown ? 'grab' : undefined }}
    >
      <div className="flex items-center gap-2 min-w-0">
        {/* Sidebar toggle (all modes) */}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); toggleSidebar(); }}
          className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
          title={state.showSidebar ? 'Hide sidebar' : 'Show sidebar'}
        >
          {state.showSidebar ? <PanelLeftClose className="h-4 w-4" /> : <PanelLeft className="h-4 w-4" />}
        </button>
        <div className="h-2 w-2 rounded-full bg-theme-success shrink-0" />
        <span className="text-sm font-semibold text-theme-primary truncate">
          {activeTab?.agentName ?? 'AI Chat'}
        </span>
      </div>

      <div className="flex items-center gap-1 shrink-0">
        {/* Schedule button */}
        {activeTab?.conversationId && (
          <div className="relative">
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); setShowSchedule(!showSchedule); }}
              className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
              title="Scheduled messages"
            >
              <Clock className="h-4 w-4" />
            </button>
            {showSchedule && (
              <ScheduledMessagesPanel
                conversationId={activeTab.conversationId}
                onClose={() => setShowSchedule(false)}
              />
            )}
          </div>
        )}

        {/* Actions menu (all modes, when a tab is active) */}
        {activeTab && (
          <div className="relative">
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); setShowActions(!showActions); }}
              className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
              title="Conversation actions"
            >
              <MoreVertical className="h-4 w-4" />
            </button>
            {showActions && (
              <div
                className="absolute right-0 top-full mt-1 z-50 bg-theme-surface border border-theme rounded-lg shadow-lg py-1 min-w-[140px]"
                onClick={(e) => e.stopPropagation()}
              >
                <button
                  type="button"
                  onClick={handlePin}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
                >
                  <Pin className="h-3.5 w-3.5" /> Pin
                </button>
                <button
                  type="button"
                  onClick={handleUnpin}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
                >
                  <PinOff className="h-3.5 w-3.5" /> Unpin
                </button>
                <button
                  type="button"
                  onClick={handleArchive}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
                >
                  <Archive className="h-3.5 w-3.5" /> Archive
                </button>
                <div className="border-t border-theme my-1" />
                <button
                  type="button"
                  onClick={handleDelete}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-danger hover:bg-theme-surface-hover transition-colors"
                >
                  <Trash2 className="h-3.5 w-3.5" /> Delete
                </button>
              </div>
            )}
          </div>
        )}

        {isDetachedMode ? (
          <button
            type="button"
            onClick={() => setMode('floating')}
            className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
            title="Dock to main window"
          >
            <ArrowDownToLine className="h-4 w-4" />
          </button>
        ) : (
          <>
            {isMaximized ? (
              <button
                type="button"
                onClick={() => setMode('floating')}
                className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                title="Restore"
              >
                <Minimize2 className="h-4 w-4" />
              </button>
            ) : (
              <button
                type="button"
                onClick={() => setMode('maximized')}
                className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                title="Maximize"
              >
                <Maximize2 className="h-4 w-4" />
              </button>
            )}
            <button
              type="button"
              onClick={() => setMode('detached')}
              className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
              title="Pop out"
            >
              <ExternalLink className="h-4 w-4" />
            </button>
          </>
        )}
        <button
          type="button"
          onClick={() => setMode('closed')}
          className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
          title="Close"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
};
