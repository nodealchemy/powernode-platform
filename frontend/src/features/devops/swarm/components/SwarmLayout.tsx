import React from 'react';
import { ClusterProvider } from '../context/ClusterContext';

interface SwarmLayoutProps {
  children: React.ReactNode;
}

export const SwarmLayout: React.FC<SwarmLayoutProps> = ({ children }) => {
  return <ClusterProvider>{children}</ClusterProvider>;
};
