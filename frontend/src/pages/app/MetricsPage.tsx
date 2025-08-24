import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';

export const MetricsPage: React.FC = () => {
MetricsPage.displayName = 'MetricsPage';
  const breadcrumbs = [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Metrics', icon: '📈' }
  ];

  return (
    <PageContainer
      title="Metrics"
      description="Key performance indicators and growth metrics."
      breadcrumbs={breadcrumbs}
    >
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Monthly Recurring Revenue</h3>
          <p className="text-3xl font-bold text-theme-primary">$12,450</p>
          <div className="flex items-center mt-2">
            <span className="text-theme-success text-sm">↑ 12.5%</span>
            <span className="text-theme-tertiary text-sm ml-2">from last month</span>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Annual Recurring Revenue</h3>
          <p className="text-3xl font-bold text-theme-primary">$149,400</p>
          <div className="flex items-center mt-2">
            <span className="text-theme-success text-sm">↑ 25.3%</span>
            <span className="text-theme-tertiary text-sm ml-2">YoY growth</span>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Average Revenue Per User</h3>
          <p className="text-3xl font-bold text-theme-primary">$89.50</p>
          <div className="flex items-center mt-2">
            <span className="text-theme-success text-sm">↑ 5.2%</span>
            <span className="text-theme-tertiary text-sm ml-2">improvement</span>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Customer Lifetime Value</h3>
          <p className="text-3xl font-bold text-theme-primary">$2,148</p>
          <div className="flex items-center mt-2">
            <span className="text-theme-success text-sm">↑ 8.7%</span>
            <span className="text-theme-tertiary text-sm ml-2">increase</span>
          </div>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Key Performance Indicators</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Growth Metrics</h3>
            <div className="space-y-4">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Customer Acquisition Rate</span>
                  <span className="text-theme-primary font-medium">15.3%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-theme-success h-2 rounded-full" style={{ width: '15.3%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Monthly Growth Rate</span>
                  <span className="text-theme-primary font-medium">8.7%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-theme-info h-2 rounded-full" style={{ width: '8.7%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Expansion Revenue</span>
                  <span className="text-theme-primary font-medium">22.4%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-theme-interactive-primary h-2 rounded-full" style={{ width: '22.4%' }} />
                </div>
              </div>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Retention Metrics</h3>
            <div className="space-y-4">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Customer Retention Rate</span>
                  <span className="text-theme-primary font-medium">92.5%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-theme-success h-2 rounded-full" style={{ width: '92.5%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Churn Rate</span>
                  <span className="text-theme-primary font-medium">2.3%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-theme-error h-2 rounded-full" style={{ width: '2.3%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Net Revenue Retention</span>
                  <span className="text-theme-primary font-medium">115%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-theme-interactive-secondary h-2 rounded-full" style={{ width: '100%' }} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};