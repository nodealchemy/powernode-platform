import React from 'react';
import { ChatWindowProvider } from '../context/ChatWindowContext';
import { ChatWindow } from '../components/ChatWindow';

export const DetachedChatPage: React.FC = () => {
  return (
    <ChatWindowProvider isDetachedMode>
      <div className="h-screen w-screen bg-theme-background">
        <ChatWindow />
      </div>
    </ChatWindowProvider>
  );
};
