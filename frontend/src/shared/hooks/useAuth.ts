import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { User } from '@/shared/services/slices/authSlice';

export interface UseAuthReturn {
  currentUser: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  permissions: string[];
}

export const useAuth = (): UseAuthReturn => {
  const { user, isLoading } = useSelector((state: RootState) => state.auth);
  
  return {
    currentUser: user,
    isAuthenticated: !!user,
    isLoading,
    permissions: user?.permissions || []
  };
};