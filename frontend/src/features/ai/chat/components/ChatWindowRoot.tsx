import React from 'react';
import { ChatWindowFloating } from './ChatWindowFloating';
import { ChatWindowMaximized } from './ChatWindowMaximized';
import { useChatWindow } from '../context/ChatWindowContext';

export const ChatWindowRoot: React.FC = () => {
  const { state } = useChatWindow();

  switch (state.mode) {
    case 'floating':
      return <ChatWindowFloating />;
    case 'maximized':
      return <ChatWindowMaximized />;
    default:
      return null;
  }
};
