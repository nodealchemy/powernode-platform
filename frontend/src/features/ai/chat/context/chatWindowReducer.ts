import type { ChatWindowState, ChatWindowAction, SplitPanel } from './chatWindowTypes';

let panelCounter = 0;
export function generatePanelId(): string {
  panelCounter += 1;
  return `panel-${Date.now()}-${panelCounter}`;
}

const defaultPanel: SplitPanel = {
  id: 'panel-default',
  tabIds: [],
  activeTabId: null,
};

export const initialChatWindowState: ChatWindowState = {
  mode: 'closed',
  preferredOpenMode: 'floating',
  tabs: [],
  activeTabId: null,
  floatingPosition: { x: -1, y: -1 },
  floatingSize: { width: 480, height: 640 },
  detachedSize: { width: 800, height: 600 },
  showSidebar: true,
  panels: [{ ...defaultPanel }],
  activePanelId: defaultPanel.id,
  panelSizes: [100],
};

function findPanelForTab(panels: SplitPanel[], tabId: string): SplitPanel | undefined {
  return panels.find(p => p.tabIds.includes(tabId));
}

function syncActiveTabId(state: ChatWindowState): string | null {
  const activePanel = state.panels.find(p => p.id === state.activePanelId);
  return activePanel?.activeTabId ?? state.panels[0]?.activeTabId ?? null;
}

export function chatWindowReducer(state: ChatWindowState, action: ChatWindowAction): ChatWindowState {
  switch (action.type) {
    case 'SET_MODE': {
      const newMode = action.payload;
      const preferredOpenMode = (newMode === 'floating' || newMode === 'maximized' || newMode === 'detached')
        ? newMode
        : state.preferredOpenMode;
      return { ...state, mode: newMode, preferredOpenMode };
    }

    case 'OPEN_TAB': {
      const tab = action.payload;
      const existing = state.tabs.find(t => t.conversationId === tab.conversationId);
      if (existing) {
        // Switch to existing tab in its panel
        const panel = findPanelForTab(state.panels, existing.id);
        const updatedPanels = panel
          ? state.panels.map(p => p.id === panel.id ? { ...p, activeTabId: existing.id } : p)
          : state.panels;
        return {
          ...state,
          activeTabId: existing.id,
          panels: updatedPanels,
          activePanelId: panel?.id ?? state.activePanelId,
        };
      }
      // Add tab to active panel
      const targetPanelId = state.activePanelId || state.panels[0]?.id;
      const newPanels = state.panels.map(p =>
        p.id === targetPanelId
          ? { ...p, tabIds: [...p.tabIds, tab.id], activeTabId: tab.id }
          : p
      );
      return {
        ...state,
        tabs: [...state.tabs, tab],
        activeTabId: tab.id,
        panels: newPanels,
      };
    }

    case 'CLOSE_TAB': {
      const tabId = action.payload;
      const filtered = state.tabs.filter(t => t.id !== tabId);

      // Remove tab from its panel
      let newPanels = state.panels.map(p => {
        if (!p.tabIds.includes(tabId)) return p;
        const newTabIds = p.tabIds.filter(id => id !== tabId);
        let newActiveTabId = p.activeTabId;
        if (p.activeTabId === tabId) {
          const closedIndex = p.tabIds.indexOf(tabId);
          newActiveTabId = newTabIds[Math.min(closedIndex, newTabIds.length - 1)] ?? null;
        }
        return { ...p, tabIds: newTabIds, activeTabId: newActiveTabId };
      });

      // Remove empty panels (except the last one)
      if (newPanels.length > 1) {
        const nonEmpty = newPanels.filter(p => p.tabIds.length > 0);
        if (nonEmpty.length > 0) {
          newPanels = nonEmpty;
        }
      }

      // Fix panel sizes
      const newPanelSizes = newPanels.length !== state.panels.length
        ? newPanels.map(() => 100 / newPanels.length)
        : state.panelSizes;

      // Fix active panel
      let newActivePanelId = state.activePanelId;
      if (!newPanels.find(p => p.id === newActivePanelId)) {
        newActivePanelId = newPanels[0]?.id ?? state.activePanelId;
      }

      const nextActiveTabId = newPanels.find(p => p.id === newActivePanelId)?.activeTabId ?? null;

      return {
        ...state,
        tabs: filtered,
        activeTabId: nextActiveTabId,
        panels: newPanels,
        panelSizes: newPanelSizes,
        activePanelId: newActivePanelId,
        mode: filtered.length === 0 ? 'closed' : state.mode,
      };
    }

    case 'SWITCH_TAB': {
      const panel = findPanelForTab(state.panels, action.payload);
      const newPanels = panel
        ? state.panels.map(p => p.id === panel.id ? { ...p, activeTabId: action.payload } : p)
        : state.panels;
      return {
        ...state,
        activeTabId: action.payload,
        panels: newPanels,
        activePanelId: panel?.id ?? state.activePanelId,
      };
    }

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

    case 'SET_DETACHED_SIZE':
      return { ...state, detachedSize: action.payload };

    case 'HYDRATE_STATE':
      return { ...action.payload };

    case 'TOGGLE_SIDEBAR':
      return { ...state, showSidebar: !state.showSidebar };

    case 'SET_SIDEBAR':
      return { ...state, showSidebar: action.payload };

    case 'CREATE_SPLIT': {
      const { tabId } = action.payload;
      if (state.panels.length >= 3) return state;

      const sourcePanel = findPanelForTab(state.panels, tabId);
      if (!sourcePanel || sourcePanel.tabIds.length < 2) return state;

      // Remove tab from source panel
      const newSourceTabIds = sourcePanel.tabIds.filter(id => id !== tabId);
      const newSourceActive = sourcePanel.activeTabId === tabId
        ? newSourceTabIds[0] ?? null
        : sourcePanel.activeTabId;

      const newPanelId = generatePanelId();
      const newPanel: SplitPanel = {
        id: newPanelId,
        tabIds: [tabId],
        activeTabId: tabId,
      };

      // Insert new panel after source
      const sourceIndex = state.panels.findIndex(p => p.id === sourcePanel.id);
      const updatedPanels = [...state.panels];
      updatedPanels[sourceIndex] = { ...sourcePanel, tabIds: newSourceTabIds, activeTabId: newSourceActive };
      updatedPanels.splice(sourceIndex + 1, 0, newPanel);

      const newSizes = updatedPanels.map(() => 100 / updatedPanels.length);

      return {
        ...state,
        panels: updatedPanels,
        panelSizes: newSizes,
        activePanelId: newPanelId,
        activeTabId: tabId,
      };
    }

    case 'CLOSE_PANEL': {
      const panelId = action.payload;
      if (state.panels.length <= 1) return state;

      const closingPanel = state.panels.find(p => p.id === panelId);
      if (!closingPanel) return state;

      // Merge tabs into the adjacent panel (prefer left neighbor)
      const closingIndex = state.panels.findIndex(p => p.id === panelId);
      const mergeIndex = closingIndex > 0 ? closingIndex - 1 : 1;
      const mergePanel = state.panels[mergeIndex];

      const newPanels = state.panels
        .map(p => {
          if (p.id === mergePanel.id) {
            return {
              ...p,
              tabIds: [...p.tabIds, ...closingPanel.tabIds],
            };
          }
          return p;
        })
        .filter(p => p.id !== panelId);

      const newSizes = newPanels.map(() => 100 / newPanels.length);
      const newActivePanelId = state.activePanelId === panelId ? mergePanel.id : state.activePanelId;

      const updatedState = {
        ...state,
        panels: newPanels,
        panelSizes: newSizes,
        activePanelId: newActivePanelId,
      };
      return { ...updatedState, activeTabId: syncActiveTabId(updatedState) };
    }

    case 'MOVE_TAB_TO_PANEL': {
      const { tabId, panelId: targetPanelId } = action.payload;
      const sourcePanel = findPanelForTab(state.panels, tabId);
      const targetPanel = state.panels.find(p => p.id === targetPanelId);
      if (!sourcePanel || !targetPanel || sourcePanel.id === targetPanelId) return state;

      let newPanels = state.panels.map(p => {
        if (p.id === sourcePanel.id) {
          const newTabIds = p.tabIds.filter(id => id !== tabId);
          const newActive = p.activeTabId === tabId ? (newTabIds[0] ?? null) : p.activeTabId;
          return { ...p, tabIds: newTabIds, activeTabId: newActive };
        }
        if (p.id === targetPanelId) {
          return { ...p, tabIds: [...p.tabIds, tabId], activeTabId: tabId };
        }
        return p;
      });

      // Remove empty panels (except the last one)
      if (newPanels.length > 1) {
        const nonEmpty = newPanels.filter(p => p.tabIds.length > 0);
        if (nonEmpty.length > 0) {
          newPanels = nonEmpty;
        }
      }

      const newSizes = newPanels.length !== state.panels.length
        ? newPanels.map(() => 100 / newPanels.length)
        : state.panelSizes;

      return {
        ...state,
        panels: newPanels,
        panelSizes: newSizes,
        activePanelId: targetPanelId,
        activeTabId: tabId,
      };
    }

    case 'SET_ACTIVE_PANEL': {
      const panel = state.panels.find(p => p.id === action.payload);
      return {
        ...state,
        activePanelId: action.payload,
        activeTabId: panel?.activeTabId ?? state.activeTabId,
      };
    }

    case 'SET_PANEL_SIZES': {
      const sizes = action.payload;
      if (sizes.length !== state.panels.length) return state;
      // Clamp each to minimum 15%
      const clamped = sizes.map(s => Math.max(15, Math.min(85, s)));
      const total = clamped.reduce((a, b) => a + b, 0);
      const normalized = clamped.map(s => (s / total) * 100);
      return { ...state, panelSizes: normalized };
    }

    case 'FOCUS_PANEL': {
      const panel = state.panels.find(p => p.id === action.payload);
      if (!panel) return state;
      return {
        ...state,
        activePanelId: action.payload,
        activeTabId: panel.activeTabId ?? state.activeTabId,
      };
    }

    default:
      return state;
  }
}
