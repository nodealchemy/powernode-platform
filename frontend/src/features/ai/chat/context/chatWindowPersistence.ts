import type { ChatWindowState, ChatBroadcastMessage } from './chatWindowTypes';
import { initialChatWindowState } from './chatWindowReducer';

const STORAGE_KEY = 'powernode_chat_window';
const CHANNEL_NAME = 'powernode_chat_sync';

export function saveChatState(state: ChatWindowState): void {
  try {
    const serialized: ChatWindowState = {
      ...state,
      mode: state.mode === 'detached' ? 'detached' : 'closed',
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(serialized));
  } catch {
    // Storage full or unavailable
  }
}

export function loadChatState(): ChatWindowState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return initialChatWindowState;
    const parsed = JSON.parse(raw) as ChatWindowState;
    return {
      ...initialChatWindowState,
      tabs: parsed.tabs ?? [],
      activeTabId: parsed.activeTabId ?? null,
      floatingPosition: parsed.floatingPosition ?? initialChatWindowState.floatingPosition,
      floatingSize: parsed.floatingSize ?? initialChatWindowState.floatingSize,
      mode: parsed.mode === 'detached' ? 'detached' : 'closed',
    };
  } catch {
    return initialChatWindowState;
  }
}

export function createBroadcastChannel(
  onMessage: (msg: ChatBroadcastMessage) => void
): { channel: BroadcastChannel; send: (msg: ChatBroadcastMessage) => void; close: () => void } | null {
  if (typeof BroadcastChannel === 'undefined') return null;
  try {
    const channel = new BroadcastChannel(CHANNEL_NAME);
    channel.onmessage = (e: MessageEvent<ChatBroadcastMessage>) => {
      onMessage(e.data);
    };
    return {
      channel,
      send: (msg: ChatBroadcastMessage) => channel.postMessage(msg),
      close: () => channel.close(),
    };
  } catch {
    return null;
  }
}
