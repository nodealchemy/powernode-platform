import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  Minimize2,
  Maximize2,
  ExternalLink,
  AppWindow,
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
  Users,
  Eraser,
} from 'lucide-react';
import { useChatWindow } from '../context/ChatWindowContext';
import { ScheduledMessagesPanel } from './ScheduledMessagesPanel';
import { WorkspaceMembersPanel } from './WorkspaceMembersPanel';
import { conversationsApi, agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ChatWindowHeaderProps {
  onPointerDown?: (e: React.PointerEvent) => void;
}

export const ChatWindowHeader: React.FC<ChatWindowHeaderProps> = ({ onPointerDown }) => {
  const { state, setMode, isDetachedMode, toggleSidebar, closeTab, openInNewTab } = useChatWindow();
  const { addNotification } = useNotifications();
  const [showActions, setShowActions] = useState(false);
  const [showSchedule, setShowSchedule] = useState(false);
  const [showMembers, setShowMembers] = useState(false);
  const [confirmAction, setConfirmAction] = useState<'archive' | 'clear' | 'delete' | null>(null);
  const membersRef = useRef<HTMLDivElement>(null);
  const actionsRef = useRef<HTMLDivElement>(null);
  const scheduleRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!showMembers && !showActions && !showSchedule) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (showMembers && membersRef.current && !membersRef.current.contains(e.target as Node)) setShowMembers(false);
      if (showActions && actionsRef.current && !actionsRef.current.contains(e.target as Node)) setShowActions(false);
      if (showSchedule && scheduleRef.current && !scheduleRef.current.contains(e.target as Node)) setShowSchedule(false);
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [showMembers, showActions, showSchedule]);

  // Reset confirm state when actions menu closes
  useEffect(() => {
    if (!showActions) setConfirmAction(null);
  }, [showActions]);

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

  const handleClearChat = useCallback(async () => {
    if (!activeTab?.agentId || !activeTab?.conversationId) return;
    try {
      await agentsApi.clearMessages(activeTab.agentId, activeTab.conversationId);
      addNotification({ type: 'success', message: 'Chat cleared' });
      // Notify the conversation component to reset its local message state
      window.dispatchEvent(new CustomEvent('powernode:chat-cleared', {
        detail: { conversationId: activeTab.conversationId }
      }));
    } catch {
      addNotification({ type: 'error', message: 'Failed to clear messages' });
    }
    setShowActions(false);
  }, [activeTab, addNotification]);

  const handleDelete = useCallback(async () => {
    if (!activeTab?.conversationId) return;
    try {
      await conversationsApi.deleteConversation(activeTab.conversationId);
      closeTab(activeTab.id);
      addNotification({ type: 'success', message: 'Conversation deleted' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to delete conversation' });
    }
    setShowActions(false);
  }, [activeTab, addNotification, closeTab]);

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
          <div className="relative" ref={scheduleRef}>
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

        {/* Workspace members (only for workspace tabs) */}
        {activeTab?.isWorkspace && activeTab?.conversationId && (
          <div className="relative" ref={membersRef}>
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); setShowMembers(!showMembers); }}
              className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
              title="Workspace members"
            >
              <Users className="h-4 w-4" />
            </button>
            {showMembers && (
              <WorkspaceMembersPanel
                conversationId={activeTab.conversationId}
                onClose={() => setShowMembers(false)}
              />
            )}
          </div>
        )}

        {/* Actions menu (all modes, when a tab is active) */}
        {activeTab && (
          <div className="relative" ref={actionsRef}>
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
                onPointerDown={(e) => e.stopPropagation()}
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
                {confirmAction === 'archive' ? (
                  <button
                    type="button"
                    onClick={() => { setConfirmAction(null); handleArchive(); }}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-white bg-theme-danger hover:bg-theme-danger/90 transition-colors"
                  >
                    <Archive className="h-3.5 w-3.5" /> Confirm Archive
                  </button>
                ) : (
                  <button
                    type="button"
                    onClick={() => setConfirmAction('archive')}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
                  >
                    <Archive className="h-3.5 w-3.5" /> Archive
                  </button>
                )}
                {confirmAction === 'clear' ? (
                  <button
                    type="button"
                    onClick={() => { setConfirmAction(null); handleClearChat(); }}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-white bg-theme-danger hover:bg-theme-danger/90 transition-colors"
                  >
                    <Eraser className="h-3.5 w-3.5" /> Confirm Clear
                  </button>
                ) : (
                  <button
                    type="button"
                    onClick={() => setConfirmAction('clear')}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
                  >
                    <Eraser className="h-3.5 w-3.5" /> Clear chat
                  </button>
                )}
                <div className="border-t border-theme my-1" />
                {confirmAction === 'delete' ? (
                  <button
                    type="button"
                    onClick={() => { setConfirmAction(null); handleDelete(); }}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-white bg-theme-danger hover:bg-theme-danger/90 transition-colors"
                  >
                    <Trash2 className="h-3.5 w-3.5" /> Confirm Delete
                  </button>
                ) : (
                  <button
                    type="button"
                    onClick={() => setConfirmAction('delete')}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-error hover:bg-theme-error-background transition-colors"
                  >
                    <Trash2 className="h-3.5 w-3.5" /> Delete
                  </button>
                )}
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
              onClick={() => openInNewTab()}
              className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
              title="Open in new tab"
            >
              <AppWindow className="h-4 w-4" />
            </button>
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
