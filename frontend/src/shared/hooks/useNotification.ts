import { useDispatch } from 'react-redux';
import { AppDispatch } from '@/shared/services';
import { addNotification } from '../services/slices/uiSlice';

type NotificationType = 'success' | 'error' | 'warning' | 'info';

interface NotificationOptions {
  type: NotificationType;
  message: string;
  details?: Record<string, unknown>;
}

export const useNotification = () => {
  const dispatch = useDispatch<AppDispatch>();

  /**
   * Show a notification
   * @param messageOrOptions - Either a string message or an options object
   * @param type - Notification type (only used when first arg is a string)
   */
  const showNotification = (
    messageOrOptions: string | NotificationOptions,
    type: NotificationType = 'info'
  ) => {
    if (typeof messageOrOptions === 'string') {
      // Called with (message, type) signature
      dispatch(addNotification({ message: messageOrOptions, type }));
    } else {
      // Called with options object { type, message, details? }
      dispatch(addNotification({
        message: messageOrOptions.message,
        type: messageOrOptions.type,
        details: messageOrOptions.details,
      }));
    }
  };

  return { showNotification };
};