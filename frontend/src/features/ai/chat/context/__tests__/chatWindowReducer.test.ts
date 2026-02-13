import { chatWindowReducer, initialChatWindowState } from '../chatWindowReducer';
import type { ChatWindowState, ChatTab } from '../chatWindowTypes';

function makeTab(id: string, conversationId?: string): ChatTab {
  return {
    id,
    agentId: `agent-${id}`,
    agentName: `Agent ${id}`,
    conversationId: conversationId ?? `conv-${id}`,
    title: `Chat ${id}`,
    unreadCount: 0,
    createdAt: Date.now(),
  };
}

function stateWith(overrides: Partial<ChatWindowState>): ChatWindowState {
  return { ...initialChatWindowState, ...overrides };
}

describe('chatWindowReducer', () => {
  describe('initial state', () => {
    it('has closed mode, no tabs, sidebar visible, one empty panel', () => {
      expect(initialChatWindowState.mode).toBe('closed');
      expect(initialChatWindowState.tabs).toEqual([]);
      expect(initialChatWindowState.showSidebar).toBe(true);
      expect(initialChatWindowState.panels).toHaveLength(1);
      expect(initialChatWindowState.panelSizes).toEqual([100]);
    });
  });

  describe('TOGGLE_SIDEBAR', () => {
    it('flips showSidebar from true to false', () => {
      const state = stateWith({ showSidebar: true });
      const result = chatWindowReducer(state, { type: 'TOGGLE_SIDEBAR' });
      expect(result.showSidebar).toBe(false);
    });

    it('flips showSidebar from false to true', () => {
      const state = stateWith({ showSidebar: false });
      const result = chatWindowReducer(state, { type: 'TOGGLE_SIDEBAR' });
      expect(result.showSidebar).toBe(true);
    });
  });

  describe('SET_SIDEBAR', () => {
    it('sets sidebar to specific value', () => {
      const state = stateWith({ showSidebar: true });
      const result = chatWindowReducer(state, { type: 'SET_SIDEBAR', payload: false });
      expect(result.showSidebar).toBe(false);
    });
  });

  describe('OPEN_TAB', () => {
    it('places new tab in the active panel', () => {
      const tab = makeTab('t1');
      const result = chatWindowReducer(initialChatWindowState, { type: 'OPEN_TAB', payload: tab });

      expect(result.tabs).toHaveLength(1);
      expect(result.activeTabId).toBe('t1');
      expect(result.panels[0].tabIds).toContain('t1');
      expect(result.panels[0].activeTabId).toBe('t1');
    });

    it('switches to existing tab if conversationId matches', () => {
      const tab = makeTab('t1', 'conv-1');
      const state = stateWith({
        tabs: [tab],
        activeTabId: 't1',
        panels: [{ id: 'p1', tabIds: ['t1'], activeTabId: 't1' }],
        activePanelId: 'p1',
      });

      const duplicate = makeTab('t2', 'conv-1');
      const result = chatWindowReducer(state, { type: 'OPEN_TAB', payload: duplicate });

      expect(result.tabs).toHaveLength(1); // No new tab added
      expect(result.activeTabId).toBe('t1'); // Switched to existing
    });
  });

  describe('CLOSE_TAB', () => {
    it('removes tab and selects next tab', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't1',
        panels: [{ id: 'p1', tabIds: ['t1', 't2'], activeTabId: 't1' }],
        activePanelId: 'p1',
        panelSizes: [100],
      });

      const result = chatWindowReducer(state, { type: 'CLOSE_TAB', payload: 't1' });

      expect(result.tabs).toHaveLength(1);
      expect(result.panels[0].tabIds).toEqual(['t2']);
      expect(result.panels[0].activeTabId).toBe('t2');
    });

    it('removes empty panel when closing last tab in multi-panel', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't2',
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        activePanelId: 'p2',
        panelSizes: [50, 50],
      });

      const result = chatWindowReducer(state, { type: 'CLOSE_TAB', payload: 't2' });

      expect(result.panels).toHaveLength(1);
      expect(result.panels[0].id).toBe('p1');
      expect(result.panelSizes).toEqual([100]);
    });

    it('closes mode when all tabs are removed', () => {
      const t1 = makeTab('t1');
      const state = stateWith({
        mode: 'maximized',
        tabs: [t1],
        activeTabId: 't1',
        panels: [{ id: 'p1', tabIds: ['t1'], activeTabId: 't1' }],
        activePanelId: 'p1',
      });

      const result = chatWindowReducer(state, { type: 'CLOSE_TAB', payload: 't1' });
      expect(result.mode).toBe('closed');
    });
  });

  describe('CREATE_SPLIT', () => {
    it('creates a new panel from tab in single panel with 2+ tabs', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't1',
        panels: [{ id: 'p1', tabIds: ['t1', 't2'], activeTabId: 't1' }],
        activePanelId: 'p1',
        panelSizes: [100],
      });

      const result = chatWindowReducer(state, {
        type: 'CREATE_SPLIT',
        payload: { tabId: 't2', direction: 'right' },
      });

      expect(result.panels).toHaveLength(2);
      expect(result.panels[0].tabIds).toEqual(['t1']);
      expect(result.panels[1].tabIds).toEqual(['t2']);
      expect(result.panelSizes).toEqual([50, 50]);
      expect(result.activeTabId).toBe('t2');
    });

    it('does not split if panel has only 1 tab', () => {
      const t1 = makeTab('t1');
      const state = stateWith({
        tabs: [t1],
        activeTabId: 't1',
        panels: [{ id: 'p1', tabIds: ['t1'], activeTabId: 't1' }],
        activePanelId: 'p1',
      });

      const result = chatWindowReducer(state, {
        type: 'CREATE_SPLIT',
        payload: { tabId: 't1', direction: 'right' },
      });

      expect(result.panels).toHaveLength(1); // No split occurred
    });

    it('does not exceed 3 panels', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const t3 = makeTab('t3');
      const t4 = makeTab('t4');
      const state = stateWith({
        tabs: [t1, t2, t3, t4],
        activeTabId: 't1',
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
          { id: 'p3', tabIds: ['t3', 't4'], activeTabId: 't3' },
        ],
        activePanelId: 'p1',
        panelSizes: [33.33, 33.33, 33.34],
      });

      const result = chatWindowReducer(state, {
        type: 'CREATE_SPLIT',
        payload: { tabId: 't4', direction: 'right' },
      });

      expect(result.panels).toHaveLength(3); // Unchanged
    });
  });

  describe('CLOSE_PANEL', () => {
    it('merges tabs into adjacent panel', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't2',
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        activePanelId: 'p2',
        panelSizes: [50, 50],
      });

      const result = chatWindowReducer(state, { type: 'CLOSE_PANEL', payload: 'p2' });

      expect(result.panels).toHaveLength(1);
      expect(result.panels[0].tabIds).toEqual(['t1', 't2']);
      expect(result.panelSizes).toEqual([100]);
    });

    it('does not close the last panel', () => {
      const state = stateWith({
        panels: [{ id: 'p1', tabIds: [], activeTabId: null }],
      });

      const result = chatWindowReducer(state, { type: 'CLOSE_PANEL', payload: 'p1' });
      expect(result.panels).toHaveLength(1);
    });
  });

  describe('MOVE_TAB_TO_PANEL', () => {
    it('moves tab between panels', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const t3 = makeTab('t3');
      const state = stateWith({
        tabs: [t1, t2, t3],
        activeTabId: 't1',
        panels: [
          { id: 'p1', tabIds: ['t1', 't2'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t3'], activeTabId: 't3' },
        ],
        activePanelId: 'p1',
        panelSizes: [50, 50],
      });

      const result = chatWindowReducer(state, {
        type: 'MOVE_TAB_TO_PANEL',
        payload: { tabId: 't1', panelId: 'p2' },
      });

      expect(result.panels[0].tabIds).toEqual(['t2']);
      expect(result.panels[1].tabIds).toEqual(['t3', 't1']);
      expect(result.activePanelId).toBe('p2');
      expect(result.activeTabId).toBe('t1');
    });

    it('removes empty source panel after move', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't1',
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        activePanelId: 'p1',
        panelSizes: [50, 50],
      });

      const result = chatWindowReducer(state, {
        type: 'MOVE_TAB_TO_PANEL',
        payload: { tabId: 't1', panelId: 'p2' },
      });

      expect(result.panels).toHaveLength(1);
      expect(result.panels[0].tabIds).toEqual(['t2', 't1']);
      expect(result.panelSizes).toEqual([100]);
    });
  });

  describe('SET_ACTIVE_PANEL', () => {
    it('sets active panel and updates activeTabId', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't1',
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        activePanelId: 'p1',
      });

      const result = chatWindowReducer(state, { type: 'SET_ACTIVE_PANEL', payload: 'p2' });

      expect(result.activePanelId).toBe('p2');
      expect(result.activeTabId).toBe('t2');
    });
  });

  describe('SET_PANEL_SIZES', () => {
    it('normalizes sizes to total 100', () => {
      const state = stateWith({
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        panelSizes: [50, 50],
      });

      const result = chatWindowReducer(state, {
        type: 'SET_PANEL_SIZES',
        payload: [60, 40],
      });

      const total = result.panelSizes.reduce((a, b) => a + b, 0);
      expect(total).toBeCloseTo(100);
    });

    it('clamps minimum to 15%', () => {
      const state = stateWith({
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        panelSizes: [50, 50],
      });

      const result = chatWindowReducer(state, {
        type: 'SET_PANEL_SIZES',
        payload: [5, 95],
      });

      expect(result.panelSizes[0]).toBeGreaterThanOrEqual(15);
    });

    it('rejects sizes array with wrong length', () => {
      const state = stateWith({
        panels: [{ id: 'p1', tabIds: [], activeTabId: null }],
        panelSizes: [100],
      });

      const result = chatWindowReducer(state, {
        type: 'SET_PANEL_SIZES',
        payload: [50, 50],
      });

      expect(result.panelSizes).toEqual([100]); // Unchanged
    });
  });

  describe('FOCUS_PANEL', () => {
    it('sets active panel and syncs active tab', () => {
      const t1 = makeTab('t1');
      const t2 = makeTab('t2');
      const state = stateWith({
        tabs: [t1, t2],
        activeTabId: 't1',
        panels: [
          { id: 'p1', tabIds: ['t1'], activeTabId: 't1' },
          { id: 'p2', tabIds: ['t2'], activeTabId: 't2' },
        ],
        activePanelId: 'p1',
      });

      const result = chatWindowReducer(state, { type: 'FOCUS_PANEL', payload: 'p2' });

      expect(result.activePanelId).toBe('p2');
      expect(result.activeTabId).toBe('t2');
    });

    it('ignores non-existent panel', () => {
      const result = chatWindowReducer(initialChatWindowState, {
        type: 'FOCUS_PANEL',
        payload: 'nonexistent',
      });
      expect(result).toEqual(initialChatWindowState);
    });
  });
});
