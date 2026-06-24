import React, { useState, useEffect } from 'react';
import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';
import { api } from '@/shared/services/api';

export const StatusPage: React.FC = () => {
  const [status, setStatus] = useState<'loading' | 'operational' | 'degraded' | 'error'>('loading');

  useEffect(() => {
    const checkHealth = async () => {
      try {
        await api.get('/health');
        setStatus('operational');
      } catch {
        setStatus('error');
      }
    };
    checkHealth();
  }, []);

  const statusConfig = new Map<typeof status, { label: string; color: string; bg: string }>([
    ['loading', { label: 'Checking...', color: 'text-theme-secondary', bg: 'bg-theme-surface' }],
    ['operational', { label: 'All Systems Operational', color: 'text-theme-success-fg', bg: 'bg-theme-success-fg/10' }],
    ['degraded', { label: 'Partial Outage', color: 'text-theme-warning-fg', bg: 'bg-theme-warning-fg/10' }],
    ['error', { label: 'Service Disruption', color: 'text-theme-error-fg', bg: 'bg-theme-error-fg/10' }],
  ]);

  const config = statusConfig.get(status) ?? statusConfig.get('loading')!;

  return (
    <PublicPageContainer title="System Status">
      <div className="max-w-2xl mx-auto">
        <div className={`rounded-xl p-6 ${config.bg} text-center`}>
          <p className={`text-xl font-semibold ${config.color}`}>
            {config.label}
          </p>
        </div>
      </div>
    </PublicPageContainer>
  );
};

export default StatusPage;
