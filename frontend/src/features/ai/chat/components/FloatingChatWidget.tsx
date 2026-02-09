import React, { useMemo } from 'react';
import { Bot } from 'lucide-react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useChatWindow } from '../context/ChatWindowContext';

export const FloatingChatWidget: React.FC = () => {
  const currentUser = useSelector((state: RootState) => state.auth.user);
  const { state, setMode } = useChatWindow();

  const hasPermission = currentUser?.permissions?.includes('ai.conversations.create');

  const totalUnread = useMemo(
    () => state.tabs.reduce((sum, t) => sum + t.unreadCount, 0),
    [state.tabs]
  );

  // Hide when chat is open in any mode, or no permission
  if (!hasPermission) return null;
  if (state.mode !== 'closed') return null;

  return (
    <div className="fixed bottom-4 right-4 z-50">
      <button
        type="button"
        onClick={() => setMode('floating')}
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
