import React, { useCallback, useRef, useEffect, useMemo } from 'react';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import { NewConversationTab } from './NewConversationTab';
import { useChatWindow } from '../context/ChatWindowContext';
import type { AiConversation } from '@/shared/types/ai';

const MIN_PANEL_WIDTH_PX = 320;
const SNAP_TOLERANCE = 3;
const SNAP_POINTS = [
  [50, 50],
  [33.33, 66.67],
  [66.67, 33.33],
  [25, 75],
  [75, 25],
  [33.33, 33.33, 33.34],
];

function snapSizes(sizes: number[]): number[] {
  for (const snap of SNAP_POINTS) {
    if (snap.length !== sizes.length) continue;
    const matches = snap.every((s, i) => Math.abs(s - sizes[i]) < SNAP_TOLERANCE);
    if (matches) return snap;
  }
  return sizes;
}

export const SplitPanelContainer: React.FC = () => {
  const { state, dispatch, setPanelSizes, setActivePanelId } = useChatWindow();
  const { panels, panelSizes, activePanelId, tabs } = state;

  const containerRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<{
    handleIndex: number;
    startX: number;
    startSizes: number[];
  } | null>(null);

  // Build conversation objects for tabs
  const tabConversations = useMemo(() => {
    const map = new Map<string, AiConversation>();
    for (const tab of tabs) {
      map.set(tab.id, {
        id: tab.conversationId,
        title: tab.title,
        status: 'active',
        ai_agent: { id: tab.agentId, name: tab.agentName, agent_type: 'assistant', is_concierge: tab.isConcierge },
        metadata: {
          created_by: '',
          total_messages: 0,
          total_tokens: 0,
          total_cost: 0,
          last_activity: new Date().toISOString(),
        },
        created_at: new Date(tab.createdAt).toISOString(),
        updated_at: new Date().toISOString(),
      });
    }
    return map;
  }, [tabs]);

  const handleNewMessage = useCallback((tabId: string) => {
    dispatch({ type: 'INCREMENT_UNREAD', payload: tabId });
  }, [dispatch]);

  const handleDragStart = useCallback((handleIndex: number, e: React.MouseEvent) => {
    e.preventDefault();
    dragRef.current = {
      handleIndex,
      startX: e.clientX,
      startSizes: [...panelSizes],
    };
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [panelSizes]);

  const handleDoubleClickDivider = useCallback(() => {
    const equalSizes = panels.map(() => 100 / panels.length);
    setPanelSizes(equalSizes);
  }, [panels, setPanelSizes]);

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const drag = dragRef.current;
      if (!drag || !containerRef.current) return;

      const containerWidth = containerRef.current.getBoundingClientRect().width;
      const minPct = (MIN_PANEL_WIDTH_PX / containerWidth) * 100;
      const deltaX = e.clientX - drag.startX;
      const deltaPct = (deltaX / containerWidth) * 100;

      const newSizes = [...drag.startSizes];
      const leftIdx = drag.handleIndex;
      const rightIdx = drag.handleIndex + 1;

      newSizes[leftIdx] = drag.startSizes[leftIdx] + deltaPct;
      newSizes[rightIdx] = drag.startSizes[rightIdx] - deltaPct;

      if (newSizes[leftIdx] < minPct || newSizes[rightIdx] < minPct) return;

      setPanelSizes(snapSizes(newSizes));
    };

    const handleMouseUp = () => {
      if (dragRef.current) {
        dragRef.current = null;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
      }
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [setPanelSizes]);

  return (
    <div ref={containerRef} className="flex-1 flex overflow-hidden" data-testid="split-panel-container">
      {panels.map((panel, i) => {
        const isActive = panel.id === activePanelId;
        const panelTabs = tabs.filter(t => panel.tabIds.includes(t.id));
        const activeTabInPanel = panel.activeTabId ? tabs.find(t => t.id === panel.activeTabId) : null;
        const conv = activeTabInPanel ? tabConversations.get(activeTabInPanel.id) : null;
        const hasNoTabs = panelTabs.length === 0;

        return (
          <React.Fragment key={panel.id}>
            <div
              style={{ width: `${panelSizes[i] ?? 100 / panels.length}%` }}
              className={`flex-shrink-0 min-w-0 flex flex-col ${
                isActive ? 'ring-1 ring-inset ring-theme-focus/40' : ''
              }`}
              onClick={() => setActivePanelId(panel.id)}
              data-testid={`split-panel-${panel.id}`}
            >
              {/* Panel content */}
              <div className="flex-1 relative overflow-hidden">
                {hasNoTabs || !conv || !activeTabInPanel ? (
                  <NewConversationTab onComplete={() => {}} />
                ) : (
                  <AgentConversationComponent
                    key={conv.id}
                    conversation={conv}
                    onNewMessage={() => handleNewMessage(activeTabInPanel.id)}
                  />
                )}
              </div>
            </div>

            {/* Divider between panels */}
            {i < panels.length - 1 && (
              <div
                className="w-1 flex-shrink-0 cursor-col-resize bg-theme-border hover:bg-theme-interactive-primary active:bg-theme-interactive-primary transition-colors"
                onMouseDown={(e) => handleDragStart(i, e)}
                onDoubleClick={handleDoubleClickDivider}
                title="Drag to resize, double-click to equalize"
                data-testid={`split-divider-${i}`}
              />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
};
