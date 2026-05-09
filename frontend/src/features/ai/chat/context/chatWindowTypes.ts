export type ChatWindowMode = 'closed' | 'floating' | 'maximized' | 'detached';

export interface ChatTab {
  id: string;
  conversationId: string;
  agentId: string;
  agentName: string;
  title: string;
  unreadCount: number;
  createdAt: number;
  isConcierge?: boolean;
  isWorkspace?: boolean;
  // M5 conversation unification — set when the tab was opened via
  // openProvisioning so ChatWindow can construct a synthetic conversation
  // with conversation_type='provisioning' for AgentConversationComponent.
  isProvisioning?: boolean;
  // Lazy-creation flag — true between openProvisioning() (client-only tab
  // open, generates UUIDv7) and the first message send (server materializes
  // the row at that id). While pending, no DB row exists; the chat surface
  // renders the synthetic conversation card from buildSyntheticConversation.
  isPending?: boolean;
  teamId?: string;
  isChannel?: boolean;
  channelId?: string;
  channelName?: string;
}

export interface FloatingPosition {
  x: number;
  y: number;
}

export interface FloatingSize {
  width: number;
  height: number;
}

export interface SplitPanel {
  id: string;
  tabIds: string[];
  activeTabId: string | null;
}

export type PreferredOpenMode = 'floating' | 'maximized' | 'detached';

export interface ChatWindowState {
  mode: ChatWindowMode;
  preferredOpenMode: PreferredOpenMode;
  preDetachMode: 'floating' | 'maximized';
  tabs: ChatTab[];
  activeTabId: string | null;
  floatingPosition: FloatingPosition;
  floatingSize: FloatingSize;
  detachedSize: FloatingSize;
  showSidebar: boolean;
  panels: SplitPanel[];
  activePanelId: string;
  panelSizes: number[];
}

export type SplitDirection = 'right';

export type ChatWindowAction =
  | { type: 'SET_MODE'; payload: ChatWindowMode }
  | { type: 'OPEN_TAB'; payload: ChatTab }
  | { type: 'CLOSE_TAB'; payload: string }
  | { type: 'SWITCH_TAB'; payload: string }
  | { type: 'UPDATE_TAB'; payload: { id: string; changes: Partial<ChatTab> } }
  | { type: 'INCREMENT_UNREAD'; payload: string }
  | { type: 'MARK_READ'; payload: string }
  | { type: 'SET_FLOATING_POSITION'; payload: FloatingPosition }
  | { type: 'SET_FLOATING_SIZE'; payload: FloatingSize }
  | { type: 'SET_DETACHED_SIZE'; payload: FloatingSize }
  | { type: 'HYDRATE_STATE'; payload: ChatWindowState }
  | { type: 'TOGGLE_SIDEBAR' }
  | { type: 'SET_SIDEBAR'; payload: boolean }
  | { type: 'CREATE_SPLIT'; payload: { tabId: string; direction: SplitDirection } }
  | { type: 'CLOSE_PANEL'; payload: string }
  | { type: 'MOVE_TAB_TO_PANEL'; payload: { tabId: string; panelId: string } }
  | { type: 'SET_ACTIVE_PANEL'; payload: string }
  | { type: 'SET_PANEL_SIZES'; payload: number[] }
  | { type: 'FOCUS_PANEL'; payload: string };

export interface ChatWindowContextValue {
  state: ChatWindowState;
  dispatch: React.Dispatch<ChatWindowAction>;
  openConversation: (agentId: string, agentName: string, conversationId?: string, tabProps?: Partial<ChatTab>) => Promise<void>;
  openConversationMaximized: (agentId: string, agentName: string, conversationId?: string, tabProps?: Partial<ChatTab>) => Promise<void>;
  openConcierge: () => Promise<void>;
  // M5 conversation unification — always opens a fresh provisioning-typed
  // conversation. Distinct from openConcierge which resumes the existing
  // concierge conversation. The new conversation appears in the sidebar's
  // Provisioning group via the conversation_type='provisioning' tag.
  openProvisioning: () => Promise<void>;
  // Lazy-creation hook — when called for a pending provisioning tab,
  // POSTs to materialize the DB row at the tab's client-allocated UUIDv7
  // and clears isPending. No-op for non-pending tabs. Called by the chat
  // surface immediately before the first message send for a pending tab.
  materializePendingTab: (tabId: string) => Promise<string | null>;
  openChannel: (channelId: string, channelName: string, teamId: string, teamName: string) => void;
  openInNewTab: () => void;
  closeTab: (tabId: string) => void;
  switchTab: (tabId: string) => void;
  setMode: (mode: ChatWindowMode) => void;
  toggleSidebar: () => void;
  createSplit: (tabId: string, direction: SplitDirection) => void;
  moveTabToPanel: (tabId: string, panelId: string) => void;
  closePanel: (panelId: string) => void;
  setActivePanelId: (id: string) => void;
  setPanelSizes: (sizes: number[]) => void;
  isDetachedMode: boolean;
}

export type ChatBroadcastMessage =
  | { type: 'detached_ready' }
  | { type: 'detached_closed' }
  | { type: 'state_sync'; payload: ChatWindowState }
  | { type: 'mode_change'; payload: ChatWindowMode }
  | { type: 'open_tab'; payload: ChatTab }
  | { type: 'detached_resize'; payload: FloatingSize };
