import React, { useState, useCallback } from 'react';
import { Loader2, Sparkles } from 'lucide-react';
import { AgentSelector } from './AgentSelector';
import { useChatWindow } from '../context/ChatWindowContext';

interface NewConversationTabProps {
  onComplete: () => void;
}

export const NewConversationTab: React.FC<NewConversationTabProps> = ({ onComplete }) => {
  const { openConversation, openConcierge } = useChatWindow();
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [loading, setLoading] = useState(false);
  const [conciergeLoading, setConciergeLoading] = useState(false);

  const handleStart = useCallback(async () => {
    if (!selectedAgentId) return;
    setLoading(true);
    try {
      await openConversation(selectedAgentId, '');
      onComplete();
    } finally {
      setLoading(false);
    }
  }, [selectedAgentId, openConversation, onComplete]);

  const handleConcierge = useCallback(async () => {
    setConciergeLoading(true);
    try {
      await openConcierge();
      onComplete();
    } finally {
      setConciergeLoading(false);
    }
  }, [openConcierge, onComplete]);

  return (
    <div className="flex flex-col items-center justify-center h-full p-6 gap-4">
      <h3 className="text-sm font-semibold text-theme-primary">New Conversation</h3>

      {/* Quick start with concierge */}
      <button
        type="button"
        onClick={handleConcierge}
        disabled={conciergeLoading}
        className="w-full max-w-xs px-4 py-3 text-sm font-medium text-white bg-theme-interactive-primary rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center justify-center gap-2"
      >
        {conciergeLoading ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <Sparkles className="h-4 w-4" />
        )}
        Quick Start with Assistant
      </button>

      <div className="flex items-center gap-3 w-full max-w-xs">
        <div className="flex-1 h-px bg-theme-border" />
        <span className="text-xs text-theme-text-tertiary">or choose an agent</span>
        <div className="flex-1 h-px bg-theme-border" />
      </div>

      <div className="w-full max-w-xs">
        <AgentSelector
          selectedAgentId={selectedAgentId}
          onSelect={setSelectedAgentId}
        />
      </div>
      <button
        type="button"
        onClick={handleStart}
        disabled={!selectedAgentId || loading}
        className="px-4 py-2 text-sm font-medium text-white bg-theme-interactive-primary rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
      >
        {loading && <Loader2 className="h-4 w-4 animate-spin" />}
        Start Conversation
      </button>
    </div>
  );
};
