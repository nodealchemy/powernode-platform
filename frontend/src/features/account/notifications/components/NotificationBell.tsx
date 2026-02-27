import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import {
  BellIcon,
  CheckIcon,
  XMarkIcon,
  InformationCircleIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  ExclamationCircleIcon,
} from '@heroicons/react/24/outline';
import { BellIcon as BellIconSolid } from '@heroicons/react/24/solid';
import { notificationApi, Notification } from '../services/notificationApi';
import { logger } from '@/shared/utils/logger';
import { RootState } from '@/shared/services';
import { useNotificationWebSocket, WebSocketNotification } from '@/shared/hooks/useNotificationWebSocket';

interface NotificationBellProps {
  className?: string;
}

const SEVERITY_ICONS: Record<string, React.ElementType> = {
  info: InformationCircleIcon,
  success: CheckCircleIcon,
  warning: ExclamationTriangleIcon,
  error: ExclamationCircleIcon,
};

const SEVERITY_COLORS: Record<string, string> = {
  info: 'text-theme-info bg-theme-info/20 dark:bg-theme-info/30',
  success: 'text-theme-success bg-theme-success/20 dark:bg-theme-success/30',
  warning: 'text-theme-warning bg-theme-warning/20 dark:bg-theme-warning/30',
  error: 'text-theme-danger bg-theme-danger/20 dark:bg-theme-danger/30',
};

export const NotificationBell: React.FC<NotificationBellProps> = ({
  className = '',
}) => {
  const { isAuthenticated } = useSelector((state: RootState) => state.auth);
  const navigate = useNavigate();
  const { openConversationMaximized } = useChatWindow();
  const [isOpen, setIsOpen] = useState(false);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Transform WebSocket notification to local Notification type
  const transformWsNotification = useCallback((wsNotif: WebSocketNotification): Notification => ({
    id: wsNotif.id,
    type: wsNotif.notification_type,
    title: wsNotif.title,
    message: wsNotif.message,
    severity: wsNotif.severity,
    action_url: wsNotif.action_url,
    action_label: wsNotif.action_label,
    icon: wsNotif.icon,
    category: wsNotif.category || 'general',
    metadata: wsNotif.metadata || {},
    read: false,
    created_at: wsNotif.created_at,
  }), []);

  // Handle notification click — open chat for AI types, navigate for others
  const handleNotificationClick = useCallback((notification: Notification) => {
    if (notification.type === 'ai_concierge_message' && notification.metadata) {
      const agentId = notification.metadata.agent_id as string | undefined;
      const conversationId = notification.metadata.conversation_id as string | undefined;
      if (agentId || conversationId) {
        setIsOpen(false);
        openConversationMaximized(agentId || '', '', conversationId);
        return;
      }
    }
    if (notification.type === 'ai_plan_review' && notification.metadata) {
      const agentId = notification.metadata.agent_id as string | undefined;
      const conversationId = notification.metadata.conversation_id as string | undefined;
      if (agentId) {
        setIsOpen(false);
        openConversationMaximized(agentId, '', conversationId);
        return;
      }
      // Mission approval notifications — navigate to mission with review flag
      if (notification.action_url) {
        setIsOpen(false);
        navigate(notification.action_url, { state: { openApproval: true } });
        return;
      }
    }
    if (notification.action_url) {
      setIsOpen(false);
      navigate(notification.action_url);
    }
  }, [navigate, openConversationMaximized]);

  // WebSocket hook for real-time notification updates
  useNotificationWebSocket({
    onNewNotification: (wsNotif: WebSocketNotification) => {
      // Add new notification to the top of the list
      setNotifications(prev => [transformWsNotification(wsNotif), ...prev.slice(0, 9)]);
      setUnreadCount(prev => prev + 1);
    },
    onNotificationRead: (notificationId: string) => {
      setNotifications(prev =>
        prev.map(n => n.id === notificationId ? { ...n, read: true } : n)
      );
      setUnreadCount(prev => Math.max(0, prev - 1));
    },
    onNotificationDismissed: (notificationId: string) => {
      setNotifications(prev => prev.filter(n => n.id !== notificationId));
      loadUnreadCount();
    },
    onError: (error: string) => {
      // Silent fail for notifications - log in dev only
      if (process.env.NODE_ENV === 'development') {
        logger.warn('[NotificationBell] WebSocket error', { error });
      }
    }
  });

  // Load notifications
  const loadNotifications = useCallback(async () => {
    try {
      const response = await notificationApi.getNotifications({ per_page: 10 });
      setNotifications(response.notifications);
      setUnreadCount(response.unread_count);
    } catch (_error) {
      // Silently fail for notifications
    }
  }, []);

  // Load unread count
  const loadUnreadCount = useCallback(async () => {
    try {
      const count = await notificationApi.getUnreadCount();
      setUnreadCount(count);
    } catch (_error) {
      // Silently fail
    }
  }, []);

  // Initial load - only when authenticated (WebSocket handles real-time updates)
  useEffect(() => {
    if (!isAuthenticated) {
      // Reset state when not authenticated
      setNotifications([]);
      setUnreadCount(0);
      return;
    }

    // Fetch initial notifications via REST API
    loadNotifications();
  }, [isAuthenticated, loadNotifications]);

  // Load full notifications when dropdown opens
  useEffect(() => {
    if (isOpen) {
      loadNotifications();
    }
  }, [isOpen, loadNotifications]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleMarkAsRead = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
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

  const handleDismiss = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await notificationApi.dismiss(id);
      setNotifications((prev) => prev.filter((n) => n.id !== id));
      // Reload count after dismiss
      loadUnreadCount();
    } catch (_error) {
      // Silently fail
    }
  };

  const handleMarkAllRead = async () => {
    setLoading(true);
    try {
      await notificationApi.markAllAsRead();
      setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
      setUnreadCount(0);
    } catch (_error) {
      // Silently fail
    } finally {
      setLoading(false);
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

  return (
    <div className={`relative ${className}`} ref={dropdownRef}>
      {/* Bell Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="relative p-2 rounded-lg text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
        aria-label="Notifications"
      >
        {unreadCount > 0 ? (
          <BellIconSolid className="h-6 w-6 text-theme-primary" />
        ) : (
          <BellIcon className="h-6 w-6" />
        )}
        {unreadCount > 0 && (
          <span className="absolute -top-0.5 -right-0.5 flex items-center justify-center h-5 w-5 text-xs font-bold text-white bg-theme-danger rounded-full">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {/* Dropdown */}
      {isOpen && (
        <div className="absolute right-0 mt-2 w-96 max-h-[32rem] bg-theme-surface rounded-xl shadow-xl border border-theme z-50 overflow-hidden flex flex-col">
          {/* Header */}
          <div className="px-4 py-3 border-b border-theme bg-theme-background flex items-center justify-between">
            <span className="text-sm font-semibold text-theme-primary">Notifications</span>
            <div className="flex items-center space-x-2">
              {unreadCount > 0 && (
                <button
                  onClick={handleMarkAllRead}
                  disabled={loading}
                  className="text-xs text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                >
                  Mark all read
                </button>
              )}
            </div>
          </div>

          {/* Notification List */}
          <div className="flex-1 overflow-y-auto">
            {notifications.length === 0 ? (
              <div className="px-4 py-8 text-center">
                <BellIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-3" />
                <p className="text-sm text-theme-secondary">No notifications</p>
                <p className="text-xs text-theme-tertiary mt-1">
                  You&apos;re all caught up!
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
                      className={`
                        px-4 py-3 hover:bg-theme-surface-hover transition-colors cursor-pointer
                        ${!notification.read ? 'bg-theme-info/10 dark:bg-theme-info/10' : ''}
                      `}
                      onClick={() => handleNotificationClick(notification)}
                    >
                      <div className="flex items-start space-x-3">
                        <div className={`p-2 rounded-lg ${colorClass}`}>
                          <Icon className="h-5 w-5" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-start justify-between">
                            <p className={`text-sm ${!notification.read ? 'font-semibold' : 'font-medium'} text-theme-primary truncate`}>
                              {notification.title}
                            </p>
                            <div className="flex items-center space-x-1 ml-2">
                              {!notification.read && (
                                <button
                                  onClick={(e) => handleMarkAsRead(notification.id, e)}
                                  className="p-1 text-theme-tertiary hover:text-theme-primary transition-colors"
                                  title="Mark as read"
                                >
                                  <CheckIcon className="h-4 w-4" />
                                </button>
                              )}
                              <button
                                onClick={(e) => handleDismiss(notification.id, e)}
                                className="p-1 text-theme-tertiary hover:text-theme-error transition-colors"
                                title="Dismiss"
                              >
                                <XMarkIcon className="h-4 w-4" />
                              </button>
                            </div>
                          </div>
                          <p className="text-xs text-theme-secondary mt-0.5 line-clamp-2">
                            {notification.message}
                          </p>
                          <div className="flex items-center justify-between mt-1">
                            <span className="text-xs text-theme-tertiary">
                              {formatTime(notification.created_at)}
                            </span>
                            {notification.action_label && (
                              <span className="text-xs text-theme-primary font-medium">
                                {notification.action_label} →
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="px-4 py-3 border-t border-theme bg-theme-background">
            <Link
              to="/app/notifications"
              onClick={() => setIsOpen(false)}
              className="block text-center text-sm text-theme-primary hover:text-theme-secondary font-medium transition-colors"
            >
              View all notifications
            </Link>
          </div>
        </div>
      )}
    </div>
  );
};

export default NotificationBell;
