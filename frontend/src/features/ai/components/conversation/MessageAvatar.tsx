import React from 'react';
import { Bot, User, Terminal, Sparkles } from 'lucide-react';
import { Avatar } from '@/shared/components/ui/Avatar';

interface MessageAvatarProps {
  senderType: 'user' | 'ai' | 'system';
  agentType?: string;
  /** Avatar size — 'sm' for compact chat, 'md' for full conversation */
  size?: 'sm' | 'md';
  className?: string;
}

/**
 * Renders the correct avatar icon based on sender type and agent type.
 * Shared between ChatMessage (floating chat) and MessageList (full conversation).
 */
export const MessageAvatar: React.FC<MessageAvatarProps> = ({
  senderType,
  agentType,
  size = 'sm',
  className = '',
}) => {
  const isUser = senderType === 'user';

  const avatarClass = isUser
    ? 'bg-theme-primary text-white'
    : 'bg-theme-surface border border-theme text-theme-primary';

  const iconSize = size === 'sm' ? 'h-4 w-4' : 'h-4 w-4';

  const icon = isUser ? (
    <User className={iconSize} aria-hidden="true" />
  ) : agentType === 'mcp_client' ? (
    <Terminal className={iconSize} aria-hidden="true" />
  ) : agentType === 'assistant' ? (
    <Sparkles className={iconSize} aria-hidden="true" />
  ) : (
    <Bot className={iconSize} aria-hidden="true" />
  );

  return (
    <Avatar size={size} fallback={isUser ? 'U' : 'AI'} className={`flex-shrink-0 mt-0.5 ${avatarClass} ${className}`}>
      <div className="flex items-center justify-center w-full h-full">
        {icon}
      </div>
    </Avatar>
  );
};
