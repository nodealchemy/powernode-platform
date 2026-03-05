import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { notificationApi, Notification } from '@/features/account/notifications/services/notificationApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useNotificationWebSocket, WebSocketNotification } from '@/shared/hooks/useNotificationWebSocket';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import {
  BellIcon,
  CheckIcon,
  XMarkIcon,
  InformationCircleIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  ExclamationCircleIcon,
  FunnelIcon,
} from '@heroicons/react/24/outline';

const SEVERITY_ICONS: Record<string, React.ElementType> = {
  info: InformationCircleIcon,
  success: CheckCircleIcon,
  warning: ExclamationTriangleIcon,
  error: ExclamationCircleIcon,
};

const SEVERITY_COLORS: Record<string, string> = {
  info: 'text-theme-info bg-theme-info/20',
  success: 'text-theme-success bg-theme-success/20',
  warning: 'text-theme-warning bg-theme-warning/20',
  error: 'text-theme-danger bg-theme-danger/20',
};

export const NotificationsPage: React.FC = () => {
  const { showNotification } = useNotifications();
  const navigate = useNavigate();
  const { openConversationMaximized } = useChatWindow();
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'unread'>('all');
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [unreadCount, setUnreadCount] = useState(0);

  // Handle new notification from WebSocket
  const handleNewNotification = useCallback((wsNotification: WebSocketNotification) => {
    // Convert WebSocket notification to API format and prepend to list
    const newNotification: Notification = {
      id: wsNotification.id,
      type: wsNotification.notification_type,
      title: wsNotification.title,
      message: wsNotification.message,
      severity: wsNotification.severity,
      action_url: wsNotification.action_url,
      action_label: wsNotification.action_label,
      icon: wsNotification.icon,
      category: wsNotification.category || 'general',
      metadata: {},
      created_at: wsNotification.created_at,
      read: false
    };

    setNotifications(prev => [newNotification, ...prev]);
    setUnreadCount(prev => prev + 1);
  }, []);

  // Handle notification marked as read from WebSocket
  const handleNotificationRead = useCallback((notificationId: string) => {
    setNotifications(prev =>
      prev.map(n => n.id === notificationId ? { ...n, read: true } : n)
    );
    setUnreadCount(prev => Math.max(0, prev - 1));
  }, []);

  // Handle notification click — open chat for AI types, navigate for others
  const handleNotificationClick = useCallback((notification: Notification) => {
    if (notification.type === 'ai_concierge_message' && notification.metadata) {
      const agentId = notification.metadata.agent_id as string | undefined;
      const conversationId = notification.metadata.conversation_id as string | undefined;
      if (agentId || conversationId) {
        openConversationMaximized(agentId || '', '', conversationId);
        return;
      }
    }
    if (notification.type === 'ai_plan_review' && notification.metadata) {
      const agentId = notification.metadata.agent_id as string | undefined;
      const conversationId = notification.metadata.conversation_id as string | undefined;
      if (agentId) {
        openConversationMaximized(agentId, '', conversationId);
        return;
      }
      if (notification.action_url) {
        navigate(notification.action_url, { state: { openApproval: true } });
        return;
      }
    }
    if (notification.action_url) {
      navigate(notification.action_url);
    }
  }, [navigate, openConversationMaximized]);

  // WebSocket connection for real-time notifications
  useNotificationWebSocket({
    onNewNotification: handleNewNotification,
    onNotificationRead: handleNotificationRead
  });

  const loadNotifications = useCallback(async () => {
    try {
      setLoading(true);
      const response = await notificationApi.getNotifications({
        page,
        per_page: 20,
        unread: filter === 'unread' ? true : undefined,
      });
      setNotifications(response.notifications);
      setUnreadCount(response.unread_count);
      setTotalPages(response.pagination.total_pages);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to load notifications', 'error');
    } finally {
      setLoading(false);
    }
   
  }, [page, filter]);

  useEffect(() => {
    loadNotifications();
  }, [loadNotifications]);

  const handleMarkAsRead = async (id: string) => {
    try {
      await notificationApi.markAsRead(id);
      setNotifications((prev) =>
        prev.map((n) => (n.id === id ? { ...n, read: true } : n))
      );
      setUnreadCount((prev) => Math.max(0, prev - 1));
    } catch (_error) {
      // Silently fail
    }
  };

  const handleDismiss = async (id: string) => {
    try {
      await notificationApi.dismiss(id);
      setNotifications((prev) => prev.filter((n) => n.id !== id));
      loadNotifications();
    } catch (_error) {
      // Silently fail
    }
  };

  const handleMarkAllRead = async () => {
    try {
      await notificationApi.markAllAsRead();
      setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
      setUnreadCount(0);
    } catch (_error) {
      // Silently fail
    }
  };

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

  if (loading && notifications.length === 0) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner size="lg" message="Loading notifications..." />
      </div>
    );
  }

  return (
    <PageContainer
      title="Notifications"
      description="View and manage your notifications"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Notifications' }
      ]}
      actions={unreadCount > 0 ? [
        {
          id: 'mark-all-read',
          label: 'Mark All Read',
          onClick: handleMarkAllRead,
          variant: 'secondary',
          icon: CheckIcon
        }
      ] : []}
    >
      <div className="space-y-6">
        {/* Filter Bar */}
        <div className="card-theme p-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <FunnelIcon className="h-5 w-5 text-theme-secondary" />
              <div className="flex gap-2">
                <button
                  onClick={() => { setFilter('all'); setPage(1); }}
                  className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors ${
                    filter === 'all'
                      ? 'bg-theme-interactive-primary text-theme-on-primary'
                      : 'bg-theme-surface text-theme-primary border border-theme hover:bg-theme-surface-hover'
                  }`}
                >
                  All
                </button>
                <button
                  onClick={() => { setFilter('unread'); setPage(1); }}
                  className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors flex items-center gap-2 ${
                    filter === 'unread'
                      ? 'bg-theme-interactive-primary text-theme-on-primary'
                      : 'bg-theme-surface text-theme-primary border border-theme hover:bg-theme-surface-hover'
                  }`}
                >
                  Unread
                  {unreadCount > 0 && (
                    <span className={`px-1.5 py-0.5 text-xs rounded-full font-semibold ${
                      filter === 'unread'
                        ? 'bg-theme-on-primary/20 text-theme-on-primary'
                        : 'bg-theme-danger text-theme-on-primary'
                    }`}>
                      {unreadCount}
                    </span>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Notifications List */}
        <div className="card-theme overflow-hidden">
          {notifications.length === 0 ? (
            <div className="px-6 py-12 text-center">
              <BellIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-3" />
              <p className="text-lg font-medium text-theme-primary">No notifications</p>
              <p className="text-sm text-theme-secondary mt-1">
                {filter === 'unread' ? "You've read all your notifications!" : "You're all caught up!"}
              </p>
            </div>
          ) : (
            <div className="divide-y divide-theme">
              {notifications.map((notification) => {
                const Icon = SEVERITY_ICONS[notification.severity] || InformationCircleIcon;
                const colorClass = SEVERITY_COLORS[notification.severity] || SEVERITY_COLORS.info;

                return (
                  <div
                    key={notification.id}
                    className={`px-6 py-4 hover:bg-theme-surface-hover transition-colors cursor-pointer ${
                      !notification.read ? 'bg-theme-info/5' : ''
                    }`}
                    onClick={() => handleNotificationClick(notification)}
                  >
                    <div className="flex items-start gap-4">
                      <div className={`p-2 rounded-lg flex-shrink-0 ${colorClass}`}>
                        <Icon className="h-5 w-5" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-start justify-between gap-4">
                          <div className="flex-1">
                            <p className={`text-sm ${!notification.read ? 'font-semibold' : 'font-medium'} text-theme-primary`}>
                              {notification.title}
                            </p>
                            <p className="text-sm text-theme-secondary mt-1">
                              {notification.message}
                            </p>
                            <div className="flex items-center gap-4 mt-2">
                              <span className="text-xs text-theme-tertiary">
                                {formatTime(notification.created_at)}
                              </span>
                              {notification.category && (
                                <span className="text-xs px-2.5 py-1 rounded-md bg-theme-primary/10 text-theme-primary font-medium border border-theme-primary/20">
                                  {notification.category}
                                </span>
                              )}
                              {notification.action_url && notification.action_label && (
                                <span
                                  className="text-xs text-theme-primary font-medium hover:underline cursor-pointer"
                                  onClick={(e) => { e.stopPropagation(); handleNotificationClick(notification); }}
                                >
                                  {notification.action_label} →
                                </span>
                              )}
                            </div>
                          </div>
                          <div className="flex items-center gap-2 flex-shrink-0">
                            {!notification.read && (
                              <button
                                onClick={() => handleMarkAsRead(notification.id)}
                                className="p-1.5 text-theme-tertiary hover:text-theme-primary hover:bg-theme-surface rounded transition-colors"
                                title="Mark as read"
                              >
                                <CheckIcon className="h-4 w-4" />
                              </button>
                            )}
                            <button
                              onClick={() => handleDismiss(notification.id)}
                              className="p-1.5 text-theme-tertiary hover:text-theme-error hover:bg-theme-surface rounded transition-colors"
                              title="Dismiss"
                            >
                              <XMarkIcon className="h-4 w-4" />
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="flex items-center justify-center gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              className="px-4 py-2 text-sm font-medium rounded-lg text-theme-secondary hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </button>
            <span className="text-sm text-theme-secondary">
              Page {page} of {totalPages}
            </span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
              className="px-4 py-2 text-sm font-medium rounded-lg text-theme-secondary hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </button>
          </div>
        )}
      </div>
    </PageContainer>
  );
};

export default NotificationsPage;
