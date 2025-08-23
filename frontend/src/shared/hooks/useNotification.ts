import { useDispatch } from 'react-redux';
import { AppDispatch } from '@/shared/services';
import { addNotification } from '../services/slices/uiSlice';

export const useNotification = () => {
  const dispatch = useDispatch<AppDispatch>();

  const showNotification = (
    message: string, 
    type: 'success' | 'error' | 'warning' | 'info' = 'info'
  ) => {
    dispatch(addNotification({ message, type }));
  };

  return { showNotification };
};