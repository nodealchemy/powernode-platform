import apiClient from '@/shared/services/apiClient';

export interface Notification {
  id: string;
  type: string;
  title: string;
  message: string;
  severity: 'info' | 'success' | 'warning' | 'error';
  action_url?: string;
  action_label?: string;
  icon?: string;
  category: string;
  metadata: Record<string, unknown>;
  read: boolean;
  read_at?: string;
  expires_at?: string;
  created_at: string;
}

export interface NotificationsResponse {
  notifications: Notification[];
  unread_count: number;
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}

export const notificationApi = {
  // Get notifications with optional filters
  getNotifications: async (params?: {
    page?: number;
    per_page?: number;
    unread?: boolean;
    category?: string;
    type?: string;
  }): Promise<NotificationsResponse> => {
    const queryParams = new URLSearchParams();
    if (params?.page) queryParams.set('page', String(params.page));
    if (params?.per_page) queryParams.set('per_page', String(params.per_page));
    if (params?.unread) queryParams.set('unread', 'true');
    if (params?.category) queryParams.set('category', params.category);
    if (params?.type) queryParams.set('type', params.type);

    const response = await apiClient.get(`/notifications?${queryParams.toString()}`);
    return response.data.data;
  },

  // Get unread count only
  getUnreadCount: async (): Promise<number> => {
    const response = await apiClient.get('/notifications/unread_count');
    return response.data.data.unread_count;
  },

  // Get single notification
  getNotification: async (id: string): Promise<Notification> => {
    const response = await apiClient.get(`/notifications/${id}`);
    return response.data.data;
  },

  // Mark notification as read
  markAsRead: async (id: string): Promise<Notification> => {
    const response = await apiClient.put(`/notifications/${id}/read`);
    return response.data.data;
  },

  // Mark notification as unread
  markAsUnread: async (id: string): Promise<Notification> => {
    const response = await apiClient.put(`/notifications/${id}/unread`);
    return response.data.data;
  },

  // Mark all as read
  markAllAsRead: async (): Promise<{ marked_count: number }> => {
    const response = await apiClient.post('/notifications/mark_all_read');
    return response.data.data;
  },

  // Dismiss notification
  dismiss: async (id: string): Promise<void> => {
    await apiClient.delete(`/notifications/${id}`);
  },

  // Dismiss all notifications
  dismissAll: async (): Promise<{ dismissed_count: number }> => {
    const response = await apiClient.delete('/notifications/dismiss_all');
    return response.data.data;
  },
};

export default notificationApi;
