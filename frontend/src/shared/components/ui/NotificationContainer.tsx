import React, { useEffect } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { removeNotification } from '@/shared/services/slices/uiSlice';
import { EnhancedNotification } from './EnhancedNotification';

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
    <div className="fixed top-4 left-1/2 transform -translate-x-1/2 z-50 flex flex-col items-center space-y-2">
      {notifications.map((notification) => (
        <EnhancedNotification
          key={notification.id}
          id={notification.id}
          type={notification.type}
          message={notification.message}
          details={notification.details}
          onRemove={handleRemove}
        />
      ))}
    </div>
  );
};