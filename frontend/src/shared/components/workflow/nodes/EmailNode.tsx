import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Mail } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { EmailNode as EmailNodeType } from '@/shared/types/workflow';

export const EmailNode: React.FC<NodeProps<EmailNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getProviderColor = () => {
    switch (data.configuration?.provider) {
      case 'gmail':
        return 'text-theme-danger bg-theme-danger/20';
      case 'outlook':
        return 'text-theme-info bg-theme-info/20';
      case 'sendgrid':
        return 'text-theme-info bg-theme-info/20';
      case 'mailgun':
        return 'text-theme-warning bg-theme-warning/20';
      case 'ses':
        return 'text-theme-warning bg-theme-warning/20';
      default:
        return 'text-theme-success bg-theme-success/20';
    }
  };

  const getProviderLabel = () => {
    switch (data.configuration?.provider) {
      case 'gmail':
        return 'Gmail';
      case 'outlook':
        return 'Outlook';
      case 'sendgrid':
        return 'SendGrid';
      case 'mailgun':
        return 'Mailgun';
      case 'ses':
        return 'AWS SES';
      default:
        return 'Email';
    }
  };

  const getSubjectPreview = () => {
    const subject = data.configuration?.subject;
    if (!subject) return 'No subject';

    return subject.length > 30 ? `${subject.substring(0, 30)}...` : subject;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-email">
        <div className="flex items-center gap-2 text-white">
          <Mail className="h-4 w-4" />
          <span className="font-medium text-sm">EMAIL</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Send Email'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Provider Badge */}
        {data.configuration?.provider && (
          <span className={`inline-block text-xs font-medium px-2 py-0.5 rounded-full ${getProviderColor()}`}>
            {getProviderLabel()}
          </span>
        )}

        {/* Subject Preview */}
        {data.configuration?.subject && (
          <div className="text-xs">
            <span className="text-theme-muted">Subject:</span>
            <span className="ml-1 text-theme-secondary">{getSubjectPreview()}</span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="email"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="email"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};