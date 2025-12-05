import React from 'react';
import {
  Bot,
  MessageSquare
} from 'lucide-react';
import { DropdownMenu, DropdownMenuItem } from '@/shared/components/ui/DropdownMenu';

export interface AIToolsMenuProps {
  nodeId: string;
  nodeType: string;
  nodeName?: string;
  isSelected?: boolean;
  hasErrors?: boolean;
  onOpenChat?: (nodeId: string) => void;
  className?: string;
}

export const AIToolsMenu: React.FC<AIToolsMenuProps> = ({
  nodeId,
  nodeType,
  nodeName,
  isSelected = false,
  hasErrors = false,
  onOpenChat,
  className = ''
}) => {
  const menuItems: DropdownMenuItem[] = [
    {
      icon: MessageSquare,
      label: 'Chat Assistant',
      onClick: () => onOpenChat?.(nodeId)
    }
  ];

  const trigger = (
    <button
      className={`
        p-1.5 rounded-md opacity-0 group-hover:opacity-100 hover:opacity-100
        hover:bg-theme-surface hover:shadow-sm border border-transparent
        hover:border-theme transition-all duration-200
        ${isSelected ? 'opacity-100' : ''}
        ${hasErrors ? 'text-theme-danger hover:text-theme-danger' : 'text-theme-interactive-primary hover:text-purple-700'}
        ${className}
      `}
      aria-label={`AI Tools for ${nodeName || nodeType} node`}
      data-dropdown-trigger="ai-tools"
    >
      <Bot className="h-4 w-4" />
    </button>
  );

  return (
    <div className="absolute top-1 right-12 z-30">
      <DropdownMenu
        trigger={trigger}
        items={menuItems}
        align="right"
        width="w-48"
        columns={1}
      />
    </div>
  );
};

// Default handlers for AI-specific actions
export const createAIToolsHandlers = (
  onOpenChat?: (nodeId: string) => void
) => {
  return {
    onOpenChat: onOpenChat || ((_nodeId: string) => {
      // Handler should be provided by parent component
    })
  };
};