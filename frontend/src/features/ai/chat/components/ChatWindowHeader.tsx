import React from 'react';
import {
  Minimize2,
  Maximize2,
  ExternalLink,
  X,
  ArrowDownToLine,
} from 'lucide-react';
import { useChatWindow } from '../context/ChatWindowContext';

interface ChatWindowHeaderProps {
  onPointerDown?: (e: React.PointerEvent) => void;
}

export const ChatWindowHeader: React.FC<ChatWindowHeaderProps> = ({ onPointerDown }) => {
  const { state, setMode, isDetachedMode } = useChatWindow();
  const activeTab = state.tabs.find(t => t.id === state.activeTabId);

  return (
    <div
      className="flex items-center justify-between px-3 py-2 border-b border-theme bg-theme-surface select-none shrink-0"
      onPointerDown={onPointerDown}
      style={{ cursor: onPointerDown ? 'grab' : undefined }}
    >
      <div className="flex items-center gap-2 min-w-0">
        <div className="h-2 w-2 rounded-full bg-theme-success shrink-0" />
        <span className="text-sm font-semibold text-theme-primary truncate">
          {activeTab?.agentName ?? 'AI Chat'}
        </span>
      </div>

      <div className="flex items-center gap-1 shrink-0">
        {isDetachedMode ? (
          <button
            type="button"
            onClick={() => {
              setMode('floating');
            }}
            className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
            title="Dock to main window"
          >
            <ArrowDownToLine className="h-4 w-4" />
          </button>
        ) : (
          <>
            {state.mode === 'maximized' ? (
              <button
                type="button"
                onClick={() => setMode('floating')}
                className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                title="Restore"
              >
                <Minimize2 className="h-4 w-4" />
              </button>
            ) : (
              <button
                type="button"
                onClick={() => setMode('maximized')}
                className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                title="Maximize"
              >
                <Maximize2 className="h-4 w-4" />
              </button>
            )}
            <button
              type="button"
              onClick={() => setMode('detached')}
              className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
              title="Pop out"
            >
              <ExternalLink className="h-4 w-4" />
            </button>
          </>
        )}
        <button
          type="button"
          onClick={() => setMode('closed')}
          className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
          title="Close"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
};
