import React, { useMemo, useCallback } from 'react';
import { Bot } from 'lucide-react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useChatWindow } from '../context/ChatWindowContext';

export const FloatingChatWidget: React.FC = () => {
  const currentUser = useSelector((state: RootState) => state.auth.user);
  const { state, setMode, openConcierge } = useChatWindow();

  const hasPermission = currentUser?.permissions?.includes('ai.conversations.create');

  const totalUnread = useMemo(
    () => state.tabs.reduce((sum, t) => sum + t.unreadCount, 0),
    [state.tabs]
  );

  const handleClick = useCallback(async () => {
    switch (state.mode) {
      case 'closed':
        if (state.tabs.length === 0) {
          await openConcierge();
        } else {
          setMode(state.preferredOpenMode);
        }
        break;
      case 'detached':
        setMode('detached');
        break;
      case 'floating':
      case 'maximized':
        setMode('closed');
        break;
    }
  }, [state.mode, state.preferredOpenMode, state.tabs.length, setMode, openConcierge]);

  if (!hasPermission) return null;

  return (
    <div className="fixed bottom-4 right-4 z-30">
      <button
        type="button"
        onClick={handleClick}
        className="relative h-12 w-12 rounded-full bg-theme-interactive-primary text-white shadow-lg hover:bg-theme-interactive-primary-hover flex items-center justify-center transition-all hover:scale-105"
        aria-label="Open AI Chat"
      >
        <Bot className="h-6 w-6" />
        {totalUnread > 0 && (
          <span className="absolute -top-1 -right-1 inline-flex items-center justify-center h-5 min-w-[20px] px-1 text-[10px] font-bold rounded-full bg-theme-danger text-white">
            {totalUnread > 99 ? '99+' : totalUnread}
          </span>
        )}
      </button>
    </div>
  );
};
