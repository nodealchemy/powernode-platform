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
              ? 'bg-green-100 text-green-800 border border-green-200'
              : notification.type === 'error'
              ? 'bg-red-100 text-red-800 border border-red-200'
              : notification.type === 'warning'
              ? 'bg-yellow-100 text-yellow-800 border border-yellow-200'
              : 'bg-blue-100 text-blue-800 border border-blue-200'
          }`}
        >
          <span className="text-sm font-medium">{notification.message}</span>
          <button
            onClick={() => handleRemove(notification.id)}
            className="ml-4 text-gray-500 hover:text-gray-700"
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