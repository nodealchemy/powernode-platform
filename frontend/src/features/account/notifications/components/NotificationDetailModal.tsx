import React from 'react';
import {
  InformationCircleIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  ExclamationCircleIcon,
  ArrowTopRightOnSquareIcon,
  ChatBubbleLeftRightIcon,
  CheckIcon,
  XMarkIcon,
} from '@heroicons/react/24/outline';
import { Modal } from '@/shared/components/ui/Modal';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';
import { ApprovalRequestPanel } from '@/shared/components/approval-chains/ApprovalRequestPanel';
import { Notification } from '../services/notificationApi';

const APPROVAL_NOTIFICATION_TYPES = [
  'autonomy_approval_required',
  'system_task_approval_required',
];

const SEVERITY_ICONS: Record<string, React.ElementType> = {
  info: InformationCircleIcon,
  success: CheckCircleIcon,
  warning: ExclamationTriangleIcon,
  error: ExclamationCircleIcon,
};

const SEVERITY_COLORS: Record<string, string> = {
  info: 'text-theme-info-fg',
  success: 'text-theme-success-fg',
  warning: 'text-theme-warning-fg',
  error: 'text-theme-danger-fg',
};

interface NotificationDetailModalProps {
  notification: Notification | null;
  onClose: () => void;
  onMarkAsRead: (id: string) => void;
  onDismiss: (id: string) => void;
  onNavigate: (url: string, state?: Record<string, unknown>) => void;
  onOpenConversation: (agentId: string, prompt: string, conversationId?: string) => void;
}

const AI_TYPES = ['ai_concierge_message', 'ai_plan_review'];

const formatTime = (dateString: string) => {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
};

export const NotificationDetailModal: React.FC<NotificationDetailModalProps> = ({
  notification,
  onClose,
  onMarkAsRead,
  onDismiss,
  onNavigate,
  onOpenConversation,
}) => {
  if (!notification) return null;

  const Icon = SEVERITY_ICONS[notification.severity] || InformationCircleIcon;
  const iconColor = SEVERITY_COLORS[notification.severity] || SEVERITY_COLORS.info;
  const isAiType = AI_TYPES.includes(notification.type);
  const hasConversation = isAiType && notification.metadata && !!(notification.metadata.agent_id || notification.metadata.conversation_id);

  const handleAction = () => {
    if (notification.type === 'ai_plan_review' && notification.action_url && !notification.metadata?.agent_id) {
      onNavigate(notification.action_url, { openApproval: true });
    } else if (notification.action_url) {
      onNavigate(notification.action_url);
    }
    onClose();
  };

  const handleOpenConversation = () => {
    const agentId = notification.metadata?.agent_id as string || '';
    const conversationId = notification.metadata?.conversation_id as string | undefined;
    onOpenConversation(agentId, '', conversationId);
    onClose();
  };

  const handleDismiss = () => {
    onDismiss(notification.id);
    onClose();
  };

  const handleMarkAsRead = () => {
    onMarkAsRead(notification.id);
  };

  return (
    <Modal
      isOpen={!!notification}
      onClose={onClose}
      variant="centered"
      size="2xl"
      title={
        <MarkdownRenderer
          content={notification.title}
          variant="admin"
          enableAdvancedFeatures={false}
          fontSize="base"
          lineHeight="tight"
          maxWidth="none"
          customComponents={{
            p: ({ children }: { children?: React.ReactNode }) => <span className="font-bold text-theme-primary">{children}</span>,
            strong: ({ children }: { children?: React.ReactNode }) => <strong className="font-extrabold">{children}</strong>,
            code: ({ children }: { children?: React.ReactNode }) => <code className="px-1.5 py-0.5 bg-theme-surface-hover rounded text-sm font-mono">{children}</code>,
          }}
        />
      }
      icon={<Icon className={`h-6 w-6 ${iconColor}`} />}
      subtitle={
        <div className="flex items-center gap-2 mt-0.5">
          {notification.category && (
            <span className="text-xs px-2 py-0.5 rounded-md bg-theme-primary/10 text-theme-primary font-medium border border-theme-primary/20">
              {notification.category}
            </span>
          )}
          <span className="text-xs text-theme-tertiary">
            {formatTime(notification.created_at)}
          </span>
        </div>
      }
      footer={
        <div className="flex items-center justify-between w-full">
          <div>
            {!notification.read && (
              <button
                onClick={handleMarkAsRead}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover rounded-lg transition-colors"
              >
                <CheckIcon className="h-4 w-4" />
                Mark as Read
              </button>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={handleDismiss}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-theme-secondary hover:text-theme-error-fg hover:bg-theme-surface-hover rounded-lg transition-colors"
            >
              <XMarkIcon className="h-4 w-4" />
              Dismiss
            </button>
            {hasConversation && (
              <button
                onClick={handleOpenConversation}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-theme-on-primary bg-theme-interactive-primary hover:bg-theme-interactive-primary-hover rounded-lg transition-colors"
              >
                <ChatBubbleLeftRightIcon className="h-4 w-4" />
                Open Conversation
              </button>
            )}
            {notification.action_url && (
              <button
                onClick={handleAction}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-theme-on-primary bg-theme-interactive-primary hover:bg-theme-interactive-primary-hover rounded-lg transition-colors"
              >
                <ArrowTopRightOnSquareIcon className="h-4 w-4" />
                {notification.action_label || 'Open'}
              </button>
            )}
          </div>
        </div>
      }
    >
      {(() => {
        const approvalRequestId = notification.metadata?.approval_request_id as string | undefined;
        const isApprovalNotification =
          APPROVAL_NOTIFICATION_TYPES.includes(notification.type) && !!approvalRequestId;

        if (isApprovalNotification && approvalRequestId) {
          return (
            <ApprovalRequestPanel
              approvalRequestId={approvalRequestId}
              onResolved={() => {
                onMarkAsRead(notification.id);
                onDismiss(notification.id);
              }}
            />
          );
        }

        return notification.message ? (
          <MarkdownRenderer
            content={notification.message}
            variant="admin"
            enableAdvancedFeatures={false}
            fontSize="base"
            lineHeight="relaxed"
            maxWidth="none"
            customComponents={{
              p: ({ children }: { children?: React.ReactNode }) => <p className="text-base text-theme-primary leading-relaxed my-2">{children}</p>,
              strong: ({ children }: { children?: React.ReactNode }) => <strong className="text-theme-primary font-semibold">{children}</strong>,
              ul: ({ children }: { children?: React.ReactNode }) => <ul className="list-disc pl-5 my-2 space-y-1">{children}</ul>,
              ol: ({ children }: { children?: React.ReactNode }) => <ol className="list-decimal pl-5 my-2 space-y-1">{children}</ol>,
              li: ({ children }: { children?: React.ReactNode }) => <li className="text-base text-theme-primary leading-relaxed">{children}</li>,
              a: ({ children, href }: { children?: React.ReactNode; href?: string }) => (
                <a href={href} className="text-theme-link hover:text-theme-link-hover underline" target="_blank" rel="noopener noreferrer">
                  {children}
                </a>
              ),
              code: ({ children }: { children?: React.ReactNode }) => <code className="px-1.5 py-0.5 bg-theme-surface-hover rounded text-sm font-mono">{children}</code>,
            }}
          />
        ) : (
          <p className="text-sm text-theme-tertiary italic">No additional details</p>
        );
      })()}
    </Modal>
  );
};

export default NotificationDetailModal;
