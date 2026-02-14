import React from 'react';
import { TeamActivityCard } from './TeamActivityCard';

export const ProviderStatusCards: React.FC = () => (
  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
    <TeamActivityCard />
  </div>
);
