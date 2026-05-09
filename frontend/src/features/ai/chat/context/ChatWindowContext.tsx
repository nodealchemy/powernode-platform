import React, { createContext, useContext, useReducer, useEffect, useCallback, useRef } from 'react';
import type {
  ChatWindowContextValue,
  ChatWindowMode,
  ChatTab,
  ChatBroadcastMessage,
  SplitDirection,
} from './chatWindowTypes';
import { chatWindowReducer, initialChatWindowState } from './chatWindowReducer';
import { saveChatState, loadChatState, createBroadcastChannel } from './chatWindowPersistence';
import { chatApi } from '../services/chatApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { uuid7 } from '@/shared/utils/uuid7';

const ChatWindowContext = createContext<ChatWindowContextValue | null>(null);

interface ChatWindowProviderProps {
  children: React.ReactNode;
  isDetachedMode?: boolean;
}

export const ChatWindowProvider: React.FC<ChatWindowProviderProps> = ({
  children,
  isDetachedMode = false,
}) => {
  const [state, dispatch] = useReducer(chatWindowReducer, initialChatWindowState, () => {
    const loaded = loadChatState();
    if (isDetachedMode) {
      return { ...loaded, mode: 'floating' as const };
    }
    return loaded;
  });

  const { addNotification } = useNotifications();
  const broadcastRef = useRef<ReturnType<typeof createBroadcastChannel>>(null);
  const detachedWindowsRef = useRef<Set<Window>>(new Set());
  const stateRef = useRef(state);
  stateRef.current = state;

  // Persist state on changes
  useEffect(() => {
    saveChatState(state);
  }, [state]);

  // BroadcastChannel setup
  useEffect(() => {
    const bc = createBroadcastChannel((msg: ChatBroadcastMessage) => {
      switch (msg.type) {
        case 'detached_ready':
          broadcastRef.current?.send({ type: 'state_sync', payload: stateRef.current });
          break;
        case 'detached_closed':
          // One detached window closed — prune closed windows from the set
          detachedWindowsRef.current.forEach(w => {
            if (w.closed) detachedWindowsRef.current.delete(w);
          });
          if (detachedWindowsRef.current.size === 0) {
            dispatch({ type: 'SET_MODE', payload: 'closed' });
          }
          break;
        case 'state_sync':
          if (isDetachedMode) {
            dispatch({ type: 'HYDRATE_STATE', payload: { ...msg.payload, mode: 'floating' } });
          }
          break;
        case 'mode_change':
          dispatch({ type: 'SET_MODE', payload: msg.payload });
          if (msg.payload === 'floating' && isDetachedMode) {
            window.close();
          }
          break;
        case 'open_tab':
          dispatch({ type: 'OPEN_TAB', payload: msg.payload });
          break;
        case 'detached_resize':
          dispatch({ type: 'SET_DETACHED_SIZE', payload: msg.payload });
          break;
      }
    });
    broadcastRef.current = bc;
    return () => bc?.close();
  }, []);

  // Close orphaned tabs whose backing conversation no longer exists. Two
  // signals trigger closure:
  //   1. AgentConversationComponent's mount-fetch hits 404 (covers stale
  //      tabs hydrated from localStorage when the row was deleted offline).
  //   2. AiConversationsListChannel pushes `conversation_destroyed` (covers
  //      live deletes from another tab/device/cleanup job).
  // Both routes converge here so tab cleanup is consistent.
  const closeTabsForConversation = useCallback((conversationId: string) => {
    const matching = stateRef.current.tabs.filter(t => t.conversationId === conversationId);
    matching.forEach(t => dispatch({ type: 'CLOSE_TAB', payload: t.id }));
  }, []);

  useEffect(() => {
    const handler = (e: Event) => {
      const id = (e as CustomEvent<{ conversationId: string }>).detail?.conversationId;
      if (id) closeTabsForConversation(id);
    };
    window.addEventListener('ai:conversation-not-found', handler);
    return () => window.removeEventListener('ai:conversation-not-found', handler);
  }, [closeTabsForConversation]);

  const webSocket = useWebSocket();
  const wsSubscribeRef = useRef(webSocket.subscribe);
  if (wsSubscribeRef.current !== webSocket.subscribe) {
    wsSubscribeRef.current = webSocket.subscribe;
  }

  useEffect(() => {
    const unsubscribe = wsSubscribeRef.current({
      channel: 'AiConversationsListChannel',
      onMessage: (data: unknown) => {
        const msg = data as { type: string; conversation_id?: string };
        if (msg.type === 'conversation_destroyed' && msg.conversation_id) {
          closeTabsForConversation(msg.conversation_id);
        }
      },
    });
    return () => unsubscribe();
  }, [closeTabsForConversation]);

  // Detached mode: signal ready on mount, track resize, signal closed on unmount
  useEffect(() => {
    if (!isDetachedMode) return;

    broadcastRef.current?.send({ type: 'detached_ready' });

    // Track window resize (debounced) and broadcast to parent
    let resizeTimer: ReturnType<typeof setTimeout>;
    const handleResize = () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        const size = { width: window.outerWidth, height: window.outerHeight };
        dispatch({ type: 'SET_DETACHED_SIZE', payload: size });
        broadcastRef.current?.send({ type: 'detached_resize', payload: size });
      }, 300);
    };
    window.addEventListener('resize', handleResize);

    const handleUnload = () => {
      // Capture final size before closing
      const size = { width: window.outerWidth, height: window.outerHeight };
      broadcastRef.current?.send({ type: 'detached_resize', payload: size });
      broadcastRef.current?.send({ type: 'detached_closed' });
    };
    window.addEventListener('beforeunload', handleUnload);

    return () => {
      clearTimeout(resizeTimer);
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('beforeunload', handleUnload);
    };
  }, [isDetachedMode]);

  // Listen for nav-item CustomEvent to open maximized
  useEffect(() => {
    const handler = () => {
      dispatch({ type: 'SET_MODE', payload: 'maximized' });
    };
    window.addEventListener('powernode:open-chat-maximized', handler);
    return () => window.removeEventListener('powernode:open-chat-maximized', handler);
  }, []);

  const openConversation = useCallback(async (agentId: string, agentName: string, conversationId?: string, tabProps?: Partial<ChatTab>) => {
    try {
      let convId = conversationId;
      if (!convId) {
        const conv = await chatApi.getOrCreateConversation(agentId);
        convId = conv.id;
      }

      const tab: ChatTab = {
        id: `tab-${convId}`,
        conversationId: convId,
        agentId,
        agentName,
        title: agentName,
        unreadCount: 0,
        createdAt: Date.now(),
        ...tabProps,
      };

      dispatch({ type: 'OPEN_TAB', payload: tab });

      if (state.mode === 'closed') {
        dispatch({ type: 'SET_MODE', payload: 'floating' });
      }

      // Sync to detached window if open
      if (state.mode === 'detached') {
        broadcastRef.current?.send({ type: 'open_tab', payload: tab });
      }
    } catch {
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: 'Failed to open conversation. Please try again.',
      });
    }
  }, [state.mode, addNotification]);

  const openConversationMaximized = useCallback(async (agentId: string, agentName: string, conversationId?: string, tabProps?: Partial<ChatTab>) => {
    try {
      let convId = conversationId;
      if (!convId) {
        const conv = await chatApi.getOrCreateConversation(agentId);
        convId = conv.id;
      }

      const tab: ChatTab = {
        id: `tab-${convId}`,
        conversationId: convId,
        agentId,
        agentName,
        title: agentName,
        unreadCount: 0,
        createdAt: Date.now(),
        ...tabProps,
      };

      dispatch({ type: 'OPEN_TAB', payload: tab });
      dispatch({ type: 'SET_MODE', payload: 'maximized' });

      // Sync to detached window if currently detached
      if (state.mode === 'detached') {
        broadcastRef.current?.send({ type: 'open_tab', payload: tab });
      }
    } catch {
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: 'Failed to open conversation. Please try again.',
      });
    }
  }, [state.mode, addNotification]);

  const openConcierge = useCallback(async () => {
    try {
      const conv = await chatApi.createConciergeConversation();
      if (!conv) {
        addNotification({
          type: 'warning',
          title: 'No Assistant',
          message: 'No concierge agent configured. Please select an agent manually.',
        });
        return;
      }

      const tab: ChatTab = {
        id: `tab-${conv.id}`,
        conversationId: conv.id,
        agentId: conv.ai_agent?.id || '',
        agentName: conv.ai_agent?.name || 'Assistant',
        title: conv.ai_agent?.name || 'Assistant',
        unreadCount: 0,
        createdAt: Date.now(),
        isConcierge: true,
      };

      dispatch({ type: 'OPEN_TAB', payload: tab });

      if (state.mode === 'closed') {
        dispatch({ type: 'SET_MODE', payload: 'floating' });
      }

      if (state.mode === 'detached') {
        broadcastRef.current?.send({ type: 'open_tab', payload: tab });
      }
    } catch {
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: 'Failed to open assistant. Please try again.',
      });
    }
  }, [state.mode, addNotification]);

  // Lazy-creation flow — generates a UUIDv7 client-side and opens the tab
  // immediately with isPending=true. No DB row yet; the synthetic conversation
  // (buildSyntheticConversation) paints the greeting card. The DB row
  // materializes server-side on first message send via materializePendingTab.
  // This stops empty provisioning conversations accumulating from button
  // clicks the user never followed through on.
  const openProvisioning = useCallback(async () => {
    const conversationId = uuid7();
    const tab: ChatTab = {
      id: `tab-${conversationId}`,
      conversationId,
      agentId: '',
      agentName: 'Provisioning',
      title: 'Provisioning',
      unreadCount: 0,
      createdAt: Date.now(),
      isConcierge: true,
      isProvisioning: true,
      isPending: true,
    };

    dispatch({ type: 'OPEN_TAB', payload: tab });

    if (state.mode === 'closed') {
      dispatch({ type: 'SET_MODE', payload: 'floating' });
    }

    if (state.mode === 'detached') {
      broadcastRef.current?.send({ type: 'open_tab', payload: tab });
    }
  }, [state.mode]);

  // Called by the chat surface immediately before sending the first message
  // on a pending provisioning tab. POSTs to /provisioning with the client-
  // allocated UUIDv7 to materialize the row at that id, then clears isPending
  // so subsequent sends use the normal path. Returns the agent_id of the
  // materialized conversation, or null on failure.
  const materializePendingTab = useCallback(async (tabId: string): Promise<string | null> => {
    const tab = stateRef.current.tabs.find(t => t.id === tabId);
    if (!tab || !tab.isPending) return tab?.agentId || null;

    try {
      const conv = await chatApi.createProvisioningConversation(tab.conversationId);
      if (!conv) {
        addNotification({
          type: 'error',
          title: 'Provisioning Error',
          message: 'No concierge agent configured. Cannot create provisioning conversation.',
        });
        return null;
      }
      const agentId = conv.ai_agent?.id || '';
      dispatch({
        type: 'UPDATE_TAB',
        payload: { id: tabId, changes: { isPending: false, agentId } },
      });
      return agentId;
    } catch {
      addNotification({
        type: 'error',
        title: 'Provisioning Error',
        message: 'Failed to start provisioning conversation. Please try again.',
      });
      return null;
    }
  }, [addNotification]);

  const openChannel = useCallback((channelId: string, channelName: string, teamId: string, teamName: string) => {
    const tabId = `tab-channel-${channelId}`;
    const existing = state.tabs.find(t => t.id === tabId);
    if (existing) {
      dispatch({ type: 'SWITCH_TAB', payload: tabId });
      if (state.mode === 'closed') {
        dispatch({ type: 'SET_MODE', payload: state.preferredOpenMode });
      }
      return;
    }

    const tab: ChatTab = {
      id: tabId,
      conversationId: channelId, // used as unique key
      agentId: '',
      agentName: teamName,
      title: `${teamName} / ${channelName}`,
      unreadCount: 0,
      createdAt: Date.now(),
      isChannel: true,
      channelId,
      channelName,
      teamId,
    };

    dispatch({ type: 'OPEN_TAB', payload: tab });

    if (state.mode === 'closed') {
      dispatch({ type: 'SET_MODE', payload: state.preferredOpenMode });
    }

    if (state.mode === 'detached') {
      broadcastRef.current?.send({ type: 'open_tab', payload: tab });
    }
  }, [state.mode, state.preferredOpenMode, state.tabs]);

  const closeTab = useCallback((tabId: string) => {
    dispatch({ type: 'CLOSE_TAB', payload: tabId });
  }, []);

  const switchTab = useCallback((tabId: string) => {
    dispatch({ type: 'SWITCH_TAB', payload: tabId });
    dispatch({ type: 'MARK_READ', payload: tabId });
  }, []);

  const setMode = useCallback((mode: ChatWindowMode) => {
    if (mode === 'detached') {
      // Prune closed windows
      detachedWindowsRef.current.forEach(w => { if (w.closed) detachedWindowsRef.current.delete(w); });
      // Focus existing popup if one is already open
      const existing = [...detachedWindowsRef.current].find(w => !w.closed);
      if (existing) {
        existing.focus();
        return;
      }
      const { width, height } = stateRef.current.detachedSize;
      const popup = window.open(
        '/chat/detached',
        'powernode_chat',
        `width=${width},height=${height},menubar=no,toolbar=no,location=no,status=no`
      );
      if (!popup) {
        addNotification({
          type: 'warning',
          title: 'Popup Blocked',
          message: 'Could not open detached chat. Please allow popups and try again.',
        });
        if (state.mode === 'closed') {
          dispatch({ type: 'SET_MODE', payload: 'maximized' });
        }
        return;
      }
      detachedWindowsRef.current.add(popup);
    }
    dispatch({ type: 'SET_MODE', payload: mode });

    // If docking back from detached — restore pre-detach mode
    if (mode === 'floating' || mode === 'maximized') {
      if (isDetachedMode) {
        // Detached window docking: tell parent to restore pre-detach mode, then close self
        const restoreMode = stateRef.current.preDetachMode || 'floating';
        broadcastRef.current?.send({ type: 'mode_change', payload: restoreMode });
        window.close();
      } else if (detachedWindowsRef.current.size > 0) {
        // Parent docking: tell detached windows to close
        broadcastRef.current?.send({ type: 'mode_change', payload: mode });
        detachedWindowsRef.current.clear();
      }
    }
  }, [addNotification, state.mode, isDetachedMode]);

  const toggleSidebar = useCallback(() => {
    dispatch({ type: 'TOGGLE_SIDEBAR' });
  }, []);

  const createSplit = useCallback((tabId: string, direction: SplitDirection) => {
    dispatch({ type: 'CREATE_SPLIT', payload: { tabId, direction } });
  }, []);

  const moveTabToPanel = useCallback((tabId: string, panelId: string) => {
    dispatch({ type: 'MOVE_TAB_TO_PANEL', payload: { tabId, panelId } });
  }, []);

  const closePanel = useCallback((panelId: string) => {
    dispatch({ type: 'CLOSE_PANEL', payload: panelId });
  }, []);

  const setActivePanelId = useCallback((id: string) => {
    dispatch({ type: 'SET_ACTIVE_PANEL', payload: id });
  }, []);

  const setPanelSizes = useCallback((sizes: number[]) => {
    dispatch({ type: 'SET_PANEL_SIZES', payload: sizes });
  }, []);

  const openInNewTab = useCallback(() => {
    // Prune closed windows and reuse existing popup
    detachedWindowsRef.current.forEach(w => { if (w.closed) detachedWindowsRef.current.delete(w); });
    const existing = [...detachedWindowsRef.current].find(w => !w.closed);
    if (existing) {
      existing.focus();
      return;
    }
    const tab = window.open('/chat/detached', 'powernode_chat');
    if (!tab) {
      addNotification({
        type: 'warning',
        title: 'Popup Blocked',
        message: 'Could not open chat in a new tab. Please allow popups and try again.',
      });
      return;
    }
    detachedWindowsRef.current.add(tab);
    dispatch({ type: 'SET_MODE', payload: 'detached' });
  }, [addNotification]);

  const value: ChatWindowContextValue = {
    state,
    dispatch,
    openConversation,
    openConversationMaximized,
    openConcierge,
    openProvisioning,
    materializePendingTab,
    openChannel,
    openInNewTab,
    closeTab,
    switchTab,
    setMode,
    toggleSidebar,
    createSplit,
    moveTabToPanel,
    closePanel,
    setActivePanelId,
    setPanelSizes,
    isDetachedMode,
  };

  return (
    <ChatWindowContext.Provider value={value}>
      {children}
    </ChatWindowContext.Provider>
  );
};

export function useChatWindow(): ChatWindowContextValue {
  const ctx = useContext(ChatWindowContext);
  if (!ctx) {
    throw new Error('useChatWindow must be used within a ChatWindowProvider');
  }
  return ctx;
}
