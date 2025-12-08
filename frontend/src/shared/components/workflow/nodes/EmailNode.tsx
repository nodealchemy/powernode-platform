import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { Mail, Send, Users, User, AtSign, Paperclip } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const EmailNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const getRecipientIcon = () => {
    switch (data.configuration?.recipientType) {
      case 'single':
        return <User className="h-4 w-4" />;
      case 'multiple':
        return <Users className="h-4 w-4" />;
      case 'list':
        return <AtSign className="h-4 w-4" />;
      default:
        return <Mail className="h-4 w-4" />;
    }
  };

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

  const getPriorityColor = () => {
    switch (data.configuration?.priority) {
      case 'high':
        return 'text-theme-danger';
      case 'low':
        return 'text-theme-success';
      default:
        return 'text-theme-info';
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
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-emerald-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-emerald-500 rounded-lg flex items-center justify-center text-white">
          <Mail className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Send Email'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.provider && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getProviderColor()}
              `}>
                {getProviderLabel()}
              </span>
            )}
            {data.configuration?.priority && data.configuration.priority !== 'normal' && (
              <span className={`text-xs font-medium ${getPriorityColor()}`}>
                {data.configuration.priority.toUpperCase()}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Subject Preview */}
      {data.configuration?.subject && (
        <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded">
          <div className="text-xs text-theme-muted mb-1">Subject:</div>
          <div className="text-sm text-theme-secondary font-medium">
            {getSubjectPreview()}
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        <div className="flex items-center gap-2">
          {getRecipientIcon()}
          <span className="text-theme-muted">
            {data.configuration?.recipientType || 'Recipients'}
          </span>
        </div>
        <div className="flex items-center gap-2">
          {data.configuration?.hasAttachments && (
            <>
              <Paperclip className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary">Has attachments</span>
            </>
          )}
          {data.configuration?.isTemplate && (
            <>
              <span className="text-theme-muted">Template-based</span>
            </>
          )}
        </div>
      </div>

      {/* Send Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-emerald-500/10 rounded-full flex items-center justify-center text-emerald-600">
          <Send className="h-4 w-4" />
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="email"
        nodeColor="bg-emerald-500"
        isEndNode={data.isEndNode}
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};