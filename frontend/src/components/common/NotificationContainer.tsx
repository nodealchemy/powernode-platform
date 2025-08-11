import React, { useEffect } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { removeNotification } from '../../store/slices/uiSlice';

export const NotificationContainer: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const notifications = useSelector((state: RootState) => state.ui.notifications);

  const handleRemove = (id: string) => {
    dispatch(removeNotification(id));
  };

  // Auto-remove notifications after 5 seconds
  useEffect(() => {
    const timeouts: NodeJS.Timeout[] = [];
    
    notifications.forEach((notification) => {
      const timeout = setTimeout(() => {
        dispatch(removeNotification(notification.id));
      }, 5000);
      timeouts.push(timeout);
    });

    // Cleanup function to clear timeouts if component unmounts or notifications change
    return () => {
      timeouts.forEach(timeout => clearTimeout(timeout));
    };
  }, [notifications, dispatch]);

  if (notifications.length === 0) return null;

  return (
    <div className="fixed top-4 right-4 z-50 space-y-2">
      {notifications.map((notification) => (
        <div
          key={notification.id}
          className={`p-4 rounded-lg shadow-lg max-w-sm flex items-center justify-between ${
            notification.type === 'success'
              ? 'bg-green-50 dark:bg-green-800 text-green-800 dark:text-green-100 border border-green-300 dark:border-green-600'
              : notification.type === 'error'
              ? 'bg-red-50 dark:bg-red-800 text-red-800 dark:text-red-100 border border-red-300 dark:border-red-600'
              : notification.type === 'warning'
              ? 'bg-yellow-50 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-100 border border-yellow-300 dark:border-yellow-600'
              : 'bg-blue-50 dark:bg-blue-800 text-blue-800 dark:text-blue-100 border border-blue-300 dark:border-blue-600'
          }`}
        >
          <span className="text-sm font-medium">{notification.message}</span>
          <button
            onClick={() => handleRemove(notification.id)}
            className={`ml-4 transition-colors duration-150 ${
              notification.type === 'success'
                ? 'text-green-600 dark:text-green-200 hover:text-green-700 dark:hover:text-green-100'
                : notification.type === 'error'
                ? 'text-red-600 dark:text-red-200 hover:text-red-700 dark:hover:text-red-100'
                : notification.type === 'warning'
                ? 'text-yellow-600 dark:text-yellow-200 hover:text-yellow-700 dark:hover:text-yellow-100'
                : 'text-blue-600 dark:text-blue-200 hover:text-blue-700 dark:hover:text-blue-100'
            }`}
          >
            <svg
              className="h-4 w-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>
      ))}
    </div>
  );
};