import React from 'react';
import { AnalyticsDashboardComponent } from '@/features/ai/components/AnalyticsDashboardComponent';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';

export const AIAnalyticsPage: React.FC = () => {
  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  return <AnalyticsDashboardComponent />;
};

export default AIAnalyticsPage;
