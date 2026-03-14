import React, { useRef, useEffect } from 'react';
import { Plus, X } from 'lucide-react';
import { useChatWindow } from '../context/ChatWindowContext';

interface ChatWindowTabsProps {
  onNewTab: () => void;
}

export const ChatWindowTabs: React.FC<ChatWindowTabsProps> = ({ onNewTab }) => {
  const { state, switchTab, closeTab } = useChatWindow();
  const scrollRef = useRef<HTMLDivElement>(null);

  // Scroll active tab into view
  useEffect(() => {
    if (!scrollRef.current || !state.activeTabId) return;
    const activeEl = scrollRef.current.querySelector(`[data-tab-id="${state.activeTabId}"]`);
    activeEl?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
  }, [state.activeTabId]);

  if (state.tabs.length <= 1) return null;

  return (
    <div className="flex items-center border-b border-theme bg-theme-surface/50 shrink-0">
      <div
        ref={scrollRef}
        className="flex-1 flex overflow-x-auto scrollbar-thin"
      >
        {state.tabs.map(tab => {
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
    </div>
  );
};
