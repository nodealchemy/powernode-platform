import React, { useRef, useEffect, useState, useCallback } from 'react';
import { Plus, X, SplitSquareHorizontal, ArrowRightLeft } from 'lucide-react';
import { useChatWindow } from '../context/ChatWindowContext';

interface ChatWindowTabsProps {
  onNewTab: () => void;
}

export const ChatWindowTabs: React.FC<ChatWindowTabsProps> = ({ onNewTab }) => {
  const { state, switchTab, closeTab, createSplit, moveTabToPanel } = useChatWindow();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [contextMenu, setContextMenu] = useState<{ tabId: string; x: number; y: number } | null>(null);

  // Scroll active tab into view
  useEffect(() => {
    if (!scrollRef.current || !state.activeTabId) return;
    const activeEl = scrollRef.current.querySelector(`[data-tab-id="${state.activeTabId}"]`);
    activeEl?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
  }, [state.activeTabId]);

  // Close context menu on outside click
  useEffect(() => {
    if (!contextMenu) return;
    const handleClick = () => setContextMenu(null);
    document.addEventListener('click', handleClick);
    return () => document.removeEventListener('click', handleClick);
  }, [contextMenu]);

  const handleContextMenu = useCallback((e: React.MouseEvent, tabId: string) => {
    e.preventDefault();
    setContextMenu({ tabId, x: e.clientX, y: e.clientY });
  }, []);

  const handleSplitRight = useCallback(() => {
    if (!contextMenu) return;
    createSplit(contextMenu.tabId, 'right');
    setContextMenu(null);
  }, [contextMenu, createSplit]);

  const handleMoveToPanel = useCallback((panelId: string) => {
    if (!contextMenu) return;
    moveTabToPanel(contextMenu.tabId, panelId);
    setContextMenu(null);
  }, [contextMenu, moveTabToPanel]);

  const handleCloseFromMenu = useCallback(() => {
    if (!contextMenu) return;
    closeTab(contextMenu.tabId);
    setContextMenu(null);
  }, [contextMenu, closeTab]);

  // Get tabs for the first panel (floating mode shows all tabs in panel[0])
  const panelTabs = state.panels[0]?.tabIds
    ? state.tabs.filter(t => state.panels[0].tabIds.includes(t.id))
    : state.tabs;

  if (panelTabs.length <= 1) return null;

  const canSplit = state.panels.length < 3 && panelTabs.length >= 2;
  const otherPanels = state.panels.filter(p => p.id !== state.panels[0]?.id);

  return (
    <div className="flex items-center border-b border-theme bg-theme-surface/50 shrink-0">
      <div
        ref={scrollRef}
        className="flex-1 flex overflow-x-auto scrollbar-thin"
      >
        {panelTabs.map(tab => {
          const isActive = tab.id === state.activeTabId;
          return (
            <button
              key={tab.id}
              type="button"
              data-tab-id={tab.id}
              onClick={() => switchTab(tab.id)}
              onAuxClick={(e) => {
                if (e.button === 1) {
                  e.preventDefault();
                  closeTab(tab.id);
                }
              }}
              onContextMenu={(e) => handleContextMenu(e, tab.id)}
              draggable
              onDragStart={(e) => {
                e.dataTransfer.setData('text/plain', tab.id);
                e.dataTransfer.effectAllowed = 'move';
              }}
              className={`group relative flex items-center gap-1.5 px-3 py-1.5 text-xs border-r border-theme whitespace-nowrap transition-colors ${
                isActive
                  ? 'bg-theme-background text-theme-primary'
                  : 'text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
              }`}
            >
              <span className="truncate max-w-[120px]">{tab.title}</span>
              {tab.unreadCount > 0 && (
                <span className="inline-flex items-center justify-center h-4 min-w-[16px] px-1 text-[10px] font-bold rounded-full bg-theme-interactive-primary text-white">
                  {tab.unreadCount > 99 ? '99+' : tab.unreadCount}
                </span>
              )}
              <span
                role="button"
                tabIndex={0}
                onClick={(e) => {
                  e.stopPropagation();
                  closeTab(tab.id);
                }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.stopPropagation();
                    closeTab(tab.id);
                  }
                }}
                className="ml-1 p-0.5 rounded opacity-0 group-hover:opacity-100 hover:bg-theme-danger/10 hover:text-theme-danger transition-all"
                title="Close tab"
              >
                <X className="h-3 w-3" />
              </span>
              {isActive && (
                <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-theme-interactive-primary" />
              )}
            </button>
          );
        })}
      </div>

      <button
        type="button"
        onClick={onNewTab}
        className="p-1.5 mx-1 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors shrink-0"
        title="New conversation"
      >
        <Plus className="h-3.5 w-3.5" />
      </button>

      {/* Context menu */}
      {contextMenu && (
        <div
          className="fixed z-50 bg-theme-surface border border-theme rounded-lg shadow-lg py-1 min-w-[160px]"
          style={{ left: contextMenu.x, top: contextMenu.y }}
          data-testid="tab-context-menu"
        >
          {canSplit && (
            <button
              type="button"
              onClick={handleSplitRight}
              className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
            >
              <SplitSquareHorizontal className="h-3.5 w-3.5" />
              Split Right
            </button>
          )}
          {otherPanels.map((p, idx) => (
            <button
              key={p.id}
              type="button"
              onClick={() => handleMoveToPanel(p.id)}
              className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-primary hover:bg-theme-surface-hover transition-colors"
            >
              <ArrowRightLeft className="h-3.5 w-3.5" />
              Move to Panel {idx + 2}
            </button>
          ))}
          <div className="border-t border-theme my-1" />
          <button
            type="button"
            onClick={handleCloseFromMenu}
            className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-theme-danger hover:bg-theme-surface-hover transition-colors"
          >
            <X className="h-3.5 w-3.5" />
            Close
          </button>
        </div>
      )}
    </div>
  );
};
