import type { ChatWindowState, ChatWindowAction } from './chatWindowTypes';

export const initialChatWindowState: ChatWindowState = {
  mode: 'closed',
  tabs: [],
  activeTabId: null,
  floatingPosition: { x: -1, y: -1 },
  floatingSize: { width: 420, height: 520 },
};

export function chatWindowReducer(state: ChatWindowState, action: ChatWindowAction): ChatWindowState {
  switch (action.type) {
    case 'SET_MODE':
      return { ...state, mode: action.payload };

    case 'OPEN_TAB': {
      const existing = state.tabs.find(t => t.conversationId === action.payload.conversationId);
      if (existing) {
        return { ...state, activeTabId: existing.id };
      }
      return {
        ...state,
        tabs: [...state.tabs, action.payload],
        activeTabId: action.payload.id,
      };
    }

    case 'CLOSE_TAB': {
      const filtered = state.tabs.filter(t => t.id !== action.payload);
      let nextActiveId = state.activeTabId;
      if (state.activeTabId === action.payload) {
        const closedIndex = state.tabs.findIndex(t => t.id === action.payload);
        nextActiveId = filtered[Math.min(closedIndex, filtered.length - 1)]?.id ?? null;
      }
      return {
        ...state,
        tabs: filtered,
        activeTabId: nextActiveId,
        mode: filtered.length === 0 ? 'closed' : state.mode,
      };
    }

    case 'SWITCH_TAB':
      return { ...state, activeTabId: action.payload };

    case 'UPDATE_TAB':
      return {
        ...state,
        tabs: state.tabs.map(t =>
          t.id === action.payload.id ? { ...t, ...action.payload.changes } : t
        ),
      };

    case 'INCREMENT_UNREAD':
      if (action.payload === state.activeTabId) return state;
      return {
        ...state,
        tabs: state.tabs.map(t =>
          t.id === action.payload ? { ...t, unreadCount: t.unreadCount + 1 } : t
        ),
      };

    case 'MARK_READ':
      return {
        ...state,
        tabs: state.tabs.map(t =>
          t.id === action.payload ? { ...t, unreadCount: 0 } : t
        ),
      };

    case 'SET_FLOATING_POSITION':
      return { ...state, floatingPosition: action.payload };

    case 'SET_FLOATING_SIZE':
      return { ...state, floatingSize: action.payload };

    case 'HYDRATE_STATE':
      return { ...action.payload };

    default:
      return state;
  }
}
