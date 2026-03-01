import React from 'react';
import { RealTimeActivityFeed } from './RealTimeActivityFeed';

export const ActiveExecutionsPanel: React.FC = () => (
  <div className="card-theme p-6">
    <RealTimeActivityFeed maxItems={8} showFilters={true} />
  </div>
);
