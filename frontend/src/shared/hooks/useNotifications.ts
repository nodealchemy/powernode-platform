// Enhanced notification hook with compatibility interface
import { useDispatch } from 'react-redux';
import { AppDispatch } from '@/shared/services';
import { addNotification as addNotificationAction } from '../services/slices/uiSlice';

interface NotificationParams {
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
  title?: string; // Optional title for compatibility
  details?: Record<string, any>; // Optional details for expandable notifications
}

export const useNotifications = () => {
  const dispatch = useDispatch<AppDispatch>();

  const addNotification = (params: NotificationParams) => {
    // If title is provided, combine with message
    const message = params.title
      ? `${params.title}: ${params.message}`
      : params.message;

    dispatch(addNotificationAction({
      type: params.type,
      message,
      details: params.details
    }));
  };

  // Compatibility helper for simpler usage
  const showNotification = (message: string, type: 'success' | 'error' | 'warning' | 'info' = 'info') => {
    addNotification({ message, type });
  };

  return { addNotification, showNotification };
};