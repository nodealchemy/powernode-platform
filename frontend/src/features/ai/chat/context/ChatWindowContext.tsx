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
  const detachedWindowRef = useRef<Window | null>(null);

  // Persist state on changes
  useEffect(() => {
    saveChatState(state);
  }, [state]);

  // BroadcastChannel setup
  useEffect(() => {
    const bc = createBroadcastChannel((msg: ChatBroadcastMessage) => {
      switch (msg.type) {
        case 'detached_ready':
          broadcastRef.current?.send({ type: 'state_sync', payload: state });
          break;
        case 'detached_closed':
          dispatch({ type: 'SET_MODE', payload: 'closed' });
          detachedWindowRef.current = null;
          break;
        case 'state_sync':
          if (isDetachedMode) {
            dispatch({ type: 'HYDRATE_STATE', payload: msg.payload });
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
      }
    });
    broadcastRef.current = bc;
    return () => bc?.close();
  }, []);  

  // Detached mode: signal ready on mount, signal closed on unmount
  useEffect(() => {
    if (isDetachedMode) {
      broadcastRef.current?.send({ type: 'detached_ready' });
      const handleUnload = () => {
        broadcastRef.current?.send({ type: 'detached_closed' });
      };
      window.addEventListener('beforeunload', handleUnload);
      return () => window.removeEventListener('beforeunload', handleUnload);
    }
  }, [isDetachedMode]);

  // Listen for nav-item CustomEvent to open maximized
  useEffect(() => {
    const handler = () => {
      dispatch({ type: 'SET_MODE', payload: 'maximized' });
    };
    window.addEventListener('powernode:open-chat-maximized', handler);
    return () => window.removeEventListener('powernode:open-chat-maximized', handler);
  }, []);

  const openConversation = useCallback(async (agentId: string, agentName: string, conversationId?: string) => {
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

  const openConversationMaximized = useCallback(async (agentId: string, agentName: string, conversationId?: string) => {
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

  const closeTab = useCallback((tabId: string) => {
    dispatch({ type: 'CLOSE_TAB', payload: tabId });
  }, []);

  const switchTab = useCallback((tabId: string) => {
    dispatch({ type: 'SWITCH_TAB', payload: tabId });
    dispatch({ type: 'MARK_READ', payload: tabId });
  }, []);

  const setMode = useCallback((mode: ChatWindowMode) => {
    if (mode === 'detached') {
      const popup = window.open(
        '/chat/detached',
        'powernode_chat',
        'width=800,height=600,menubar=no,toolbar=no,location=no,status=no'
      );
      if (!popup) {
        addNotification({
          type: 'warning',
          title: 'Popup Blocked',
          message: 'Could not open detached chat. Please allow popups and try again.',
        });
        dispatch({ type: 'SET_MODE', payload: 'maximized' });
        return;
      }
      detachedWindowRef.current = popup;
    }
    dispatch({ type: 'SET_MODE', payload: mode });

    // If docking back from detached, notify the popup
    if (mode === 'floating' && detachedWindowRef.current) {
      broadcastRef.current?.send({ type: 'mode_change', payload: 'floating' });
      detachedWindowRef.current = null;
    }
  }, [addNotification]);

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

  const value: ChatWindowContextValue = {
    state,
    dispatch,
    openConversation,
    openConversationMaximized,
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
