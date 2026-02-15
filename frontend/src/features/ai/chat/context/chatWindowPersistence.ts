import type { ChatWindowState, ChatBroadcastMessage, SplitPanel, PreferredOpenMode } from './chatWindowTypes';
import { initialChatWindowState } from './chatWindowReducer';

const STORAGE_KEY = 'powernode_chat_window';
const CHANNEL_NAME = 'powernode_chat_sync';

export function saveChatState(state: ChatWindowState): void {
  try {
    const serialized: ChatWindowState = {
      ...state,
      mode: 'closed',
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(serialized));
  } catch {
    // Storage full or unavailable
  }
}

/**
 * Migrate old flat-tabs format (no panels) to single-panel format.
 */
function migrateLegacyState(parsed: Record<string, unknown>): Partial<ChatWindowState> {
  const tabs = (parsed.tabs ?? []) as ChatWindowState['tabs'];
  const activeTabId = (parsed.activeTabId ?? null) as string | null;

  // If panels already exist, no migration needed
  if (Array.isArray(parsed.panels) && parsed.panels.length > 0) {
    return {
      panels: parsed.panels as SplitPanel[],
      activePanelId: (parsed.activePanelId as string) || (parsed.panels as SplitPanel[])[0]?.id || 'panel-default',
      panelSizes: (parsed.panelSizes as number[]) || [100],
      showSidebar: typeof parsed.showSidebar === 'boolean' ? parsed.showSidebar : true,
    };
  }

  // Legacy: wrap all tabs into a single panel
  const panel: SplitPanel = {
    id: 'panel-default',
    tabIds: tabs.map(t => t.id),
    activeTabId,
  };

  return {
    panels: [panel],
    activePanelId: panel.id,
    panelSizes: [100],
    showSidebar: true,
  };
}

export function loadChatState(): ChatWindowState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return initialChatWindowState;
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const migrated = migrateLegacyState(parsed);

    const preferredOpenMode: PreferredOpenMode =
      parsed.preferredOpenMode === 'detached' ? 'detached' : 'floating';

    return {
      ...initialChatWindowState,
      tabs: (parsed.tabs as ChatWindowState['tabs']) ?? [],
      activeTabId: (parsed.activeTabId as string | null) ?? null,
      floatingPosition: (parsed.floatingPosition as ChatWindowState['floatingPosition']) ?? initialChatWindowState.floatingPosition,
      floatingSize: (parsed.floatingSize as ChatWindowState['floatingSize']) ?? initialChatWindowState.floatingSize,
      mode: 'closed',
      preferredOpenMode,
      showSidebar: migrated.showSidebar ?? true,
      panels: migrated.panels ?? initialChatWindowState.panels,
      activePanelId: migrated.activePanelId ?? initialChatWindowState.activePanelId,
      panelSizes: migrated.panelSizes ?? initialChatWindowState.panelSizes,
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
