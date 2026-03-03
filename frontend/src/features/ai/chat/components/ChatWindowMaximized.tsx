import React, { useEffect } from 'react';
import { ChatWindow } from './ChatWindow';
import { useChatWindow } from '../context/ChatWindowContext';

export const ChatWindowMaximized: React.FC = () => {
  const { setMode } = useChatWindow();

  // Escape key restores to floating
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setMode('floating');
      }
    };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [setMode]);

  // Lock body scroll
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, []);

  return (
    <div className="fixed inset-0 top-16 z-40 bg-theme-background">
      <ChatWindow />
    </div>
  );
};
