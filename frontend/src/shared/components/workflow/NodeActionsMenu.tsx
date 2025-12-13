import React from 'react';
import {
  MoreVertical,
  MessageSquare,
  Link,
  Trash2
} from 'lucide-react';
import { DropdownMenu, DropdownMenuItem } from '@/shared/components/ui/DropdownMenu';

export interface NodeActionsMenuProps {
  nodeId: string;
  nodeType: string;
  nodeName?: string;
  isSelected?: boolean;
  hasErrors?: boolean;
  onOpenChat?: (nodeId: string) => void;
  onDelete?: (nodeId: string) => void;
  onCopyId?: (nodeId: string) => void;
  className?: string;
}

export const NodeActionsMenu: React.FC<NodeActionsMenuProps> = ({
  nodeId,
  nodeType,
  nodeName,
  isSelected = false,
  hasErrors = false,
  onOpenChat,
  onDelete,
  onCopyId,
  className = ''
}) => {
  const menuItems: DropdownMenuItem[] = [
    // AI Actions
    {
      icon: MessageSquare,
      label: 'Chat Assistant',
      onClick: () => onOpenChat?.(nodeId)
    },
    // Divider
    {
      divider: true,
      label: '',
      onClick: () => {}
    },
    // Node Actions
    {
      icon: Link,
      label: 'Copy Node ID',
      onClick: () => onCopyId?.(nodeId)
    },
    {
      icon: Trash2,
      label: 'Delete Node',
      onClick: () => onDelete?.(nodeId),
      danger: true
    }
  ];

  const trigger = (
    <button
      className={`
        p-1.5 rounded-md opacity-0 group-hover:opacity-100 hover:opacity-100
        hover:bg-theme-surface hover:shadow-sm border border-transparent
        hover:border-theme transition-all duration-200
        ${isSelected ? 'opacity-100' : ''}
        ${hasErrors ? 'text-theme-danger hover:text-theme-danger' : 'text-theme-secondary hover:text-theme-primary'}
        ${className}
      `}
      aria-label={`Actions for ${nodeName || nodeType} node`}
      data-dropdown-trigger="node-actions"
    >
      <MoreVertical className="h-4 w-4" />
    </button>
  );

  return (
    <div className="absolute top-1 right-1 z-30">
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

// Default handlers for combined actions
export const createNodeActionsHandlers = (
  onNodeDelete?: (nodeId: string) => void,
  onNotify?: (message: string, type?: 'success' | 'error' | 'info') => void
) => {
  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      onNotify?.('Copied to clipboard', 'success');
    } catch (error) {
      onNotify?.('Failed to copy to clipboard', 'error');
    }
  };

  return {
    onDelete: (nodeId: string) => {
      if (window.confirm('Are you sure you want to delete this node?')) {
        onNodeDelete?.(nodeId);
        onNotify?.('Node deleted', 'success');
      }
    },

    onCopyId: (nodeId: string) => {
      copyToClipboard(nodeId);
    },

    onOpenChat: (_nodeId: string) => {
      // Handler should be provided by parent component
    }
  };
};
