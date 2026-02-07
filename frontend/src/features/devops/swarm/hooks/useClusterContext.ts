import { useContext } from 'react';
import { ClusterContext } from '../context/ClusterContext';

export function useClusterContext() {
  const context = useContext(ClusterContext);
  if (!context) {
    throw new Error('useClusterContext must be used within a ClusterProvider');
  }
  return context;
}
