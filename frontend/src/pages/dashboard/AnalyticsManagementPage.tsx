import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { AnalyticsPage } from './AnalyticsPage';
import { ReportsPage } from './ReportsPage';

const tabs = [
  { id: 'overview', label: 'Overview', path: '/dashboard/analytics/overview', icon: '📊' },
  { id: 'metrics', label: 'Metrics', path: '/dashboard/analytics/metrics', icon: '📈' },
  { id: 'reports', label: 'Reports', path: '/dashboard/analytics/reports', icon: '📄' },
  { id: 'revenue', label: 'Revenue', path: '/dashboard/analytics/revenue', icon: '💰' },
  { id: 'customers', label: 'Customer Analytics', path: '/dashboard/analytics/customers', icon: '👥' },
  { id: 'forecasting', label: 'Forecasting', path: '/dashboard/analytics/forecasting', icon: '🔮' },
];

const MetricsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Monthly Recurring Revenue</h3>
          <p className="text-3xl font-bold text-theme-primary">$12,450</p>
          <div className="flex items-center mt-2">
            <span className="text-green-500 text-sm">↑ 12.5%</span>
            <span className="text-theme-tertiary text-sm ml-2">from last month</span>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Annual Recurring Revenue</h3>
          <p className="text-3xl font-bold text-theme-primary">$149,400</p>
          <div className="flex items-center mt-2">
            <span className="text-green-500 text-sm">↑ 25.3%</span>
            <span className="text-theme-tertiary text-sm ml-2">YoY growth</span>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Average Revenue Per User</h3>
          <p className="text-3xl font-bold text-theme-primary">$89.50</p>
          <div className="flex items-center mt-2">
            <span className="text-green-500 text-sm">↑ 5.2%</span>
            <span className="text-theme-tertiary text-sm ml-2">improvement</span>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-sm font-medium text-theme-tertiary mb-2">Customer Lifetime Value</h3>
          <p className="text-3xl font-bold text-theme-primary">$2,148</p>
          <div className="flex items-center mt-2">
            <span className="text-green-500 text-sm">↑ 8.7%</span>
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
                  <div className="bg-green-500 h-2 rounded-full" style={{ width: '15.3%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Monthly Growth Rate</span>
                  <span className="text-theme-primary font-medium">8.7%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-blue-500 h-2 rounded-full" style={{ width: '8.7%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Expansion Revenue</span>
                  <span className="text-theme-primary font-medium">22.4%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-purple-500 h-2 rounded-full" style={{ width: '22.4%' }} />
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
                  <div className="bg-green-500 h-2 rounded-full" style={{ width: '92.5%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Churn Rate</span>
                  <span className="text-theme-primary font-medium">2.3%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-red-500 h-2 rounded-full" style={{ width: '2.3%' }} />
                </div>
              </div>
              
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Net Revenue Retention</span>
                  <span className="text-theme-primary font-medium">115%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-indigo-500 h-2 rounded-full" style={{ width: '100%' }} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const RevenuePage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Revenue Analysis</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Total Revenue</h3>
            <p className="text-2xl font-bold text-theme-primary">$124,500</p>
            <p className="text-xs text-theme-success mt-1">↑ 15.3% from last period</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Recurring Revenue</h3>
            <p className="text-2xl font-bold text-theme-primary">$98,200</p>
            <p className="text-xs text-theme-tertiary mt-1">78.9% of total</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">One-time Revenue</h3>
            <p className="text-2xl font-bold text-theme-primary">$26,300</p>
            <p className="text-xs text-theme-tertiary mt-1">21.1% of total</p>
          </div>
        </div>

        <div className="mb-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Revenue by Plan</h3>
          <div className="space-y-3">
            <div>
              <div className="flex justify-between text-sm mb-1">
                <span className="text-theme-secondary">Enterprise Plan</span>
                <span className="text-theme-primary font-medium">$65,400 (52.5%)</span>
              </div>
              <div className="w-full bg-theme-background rounded-full h-3">
                <div className="bg-purple-500 h-3 rounded-full" style={{ width: '52.5%' }} />
              </div>
            </div>
            <div>
              <div className="flex justify-between text-sm mb-1">
                <span className="text-theme-secondary">Professional Plan</span>
                <span className="text-theme-primary font-medium">$38,900 (31.2%)</span>
              </div>
              <div className="w-full bg-theme-background rounded-full h-3">
                <div className="bg-blue-500 h-3 rounded-full" style={{ width: '31.2%' }} />
              </div>
            </div>
            <div>
              <div className="flex justify-between text-sm mb-1">
                <span className="text-theme-secondary">Starter Plan</span>
                <span className="text-theme-primary font-medium">$20,200 (16.3%)</span>
              </div>
              <div className="w-full bg-theme-background rounded-full h-3">
                <div className="bg-green-500 h-3 rounded-full" style={{ width: '16.3%' }} />
              </div>
            </div>
          </div>
        </div>

        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Revenue Trends</h3>
          <div className="bg-theme-background rounded-lg p-8 text-center">
            <span className="text-4xl">📈</span>
            <p className="text-theme-secondary mt-2">Revenue chart will be displayed here</p>
            <p className="text-theme-tertiary text-sm mt-1">
              Showing monthly revenue trends over the past 12 months
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

const CustomerAnalyticsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Customer Analytics</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Total Customers</h3>
            <p className="text-2xl font-bold text-theme-primary">1,392</p>
            <p className="text-xs text-theme-success mt-1">↑ 124 new this month</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Active Users</h3>
            <p className="text-2xl font-bold text-theme-primary">1,287</p>
            <p className="text-xs text-theme-tertiary mt-1">92.5% engagement</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Avg Session Time</h3>
            <p className="text-2xl font-bold text-theme-primary">24m 36s</p>
            <p className="text-xs text-theme-success mt-1">↑ 3m from last month</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">NPS Score</h3>
            <p className="text-2xl font-bold text-theme-primary">72</p>
            <p className="text-xs text-theme-success mt-1">Excellent</p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Customer Segments</h3>
            <div className="space-y-3">
              <div className="bg-theme-background rounded-lg p-3 flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">Enterprise</p>
                  <p className="text-sm text-theme-secondary">245 customers</p>
                </div>
                <span className="text-2xl">🏢</span>
              </div>
              <div className="bg-theme-background rounded-lg p-3 flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">Small Business</p>
                  <p className="text-sm text-theme-secondary">687 customers</p>
                </div>
                <span className="text-2xl">🏪</span>
              </div>
              <div className="bg-theme-background rounded-lg p-3 flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">Individual</p>
                  <p className="text-sm text-theme-secondary">460 customers</p>
                </div>
                <span className="text-2xl">👤</span>
              </div>
            </div>
          </div>
          
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Customer Health</h3>
            <div className="space-y-3">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Healthy</span>
                  <span className="text-green-600 font-medium">78%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-green-500 h-2 rounded-full" style={{ width: '78%' }} />
                </div>
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">At Risk</span>
                  <span className="text-yellow-600 font-medium">15%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-yellow-500 h-2 rounded-full" style={{ width: '15%' }} />
                </div>
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Churning</span>
                  <span className="text-red-600 font-medium">7%</span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div className="bg-red-500 h-2 rounded-full" style={{ width: '7%' }} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const ForecastingPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Revenue Forecasting</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Q2 2024 Forecast</h3>
            <p className="text-2xl font-bold text-theme-primary">$385,000</p>
            <p className="text-xs text-theme-success mt-1">95% confidence interval</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">2024 Annual Forecast</h3>
            <p className="text-2xl font-bold text-theme-primary">$1.65M</p>
            <p className="text-xs text-theme-success mt-1">↑ 35% YoY growth</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Break-even Point</h3>
            <p className="text-2xl font-bold text-theme-primary">Q3 2024</p>
            <p className="text-xs text-theme-tertiary mt-1">Based on current growth</p>
          </div>
        </div>

        <div className="mb-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Growth Scenarios</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-theme-background rounded-lg p-4 border-l-4 border-red-500">
              <h4 className="font-medium text-theme-primary mb-2">Conservative</h4>
              <p className="text-xl font-bold text-theme-primary">$1.35M</p>
              <p className="text-sm text-theme-secondary mt-1">15% growth rate</p>
              <p className="text-xs text-theme-tertiary mt-2">Based on historical minimums</p>
            </div>
            <div className="bg-theme-background rounded-lg p-4 border-l-4 border-yellow-500">
              <h4 className="font-medium text-theme-primary mb-2">Realistic</h4>
              <p className="text-xl font-bold text-theme-primary">$1.65M</p>
              <p className="text-sm text-theme-secondary mt-1">35% growth rate</p>
              <p className="text-xs text-theme-tertiary mt-2">Based on current trends</p>
            </div>
            <div className="bg-theme-background rounded-lg p-4 border-l-4 border-green-500">
              <h4 className="font-medium text-theme-primary mb-2">Optimistic</h4>
              <p className="text-xl font-bold text-theme-primary">$2.1M</p>
              <p className="text-sm text-theme-secondary mt-1">55% growth rate</p>
              <p className="text-xs text-theme-tertiary mt-2">With successful expansion</p>
            </div>
          </div>
        </div>

        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Key Assumptions</h3>
          <div className="bg-theme-background rounded-lg p-4">
            <ul className="space-y-2 text-sm text-theme-secondary">
              <li className="flex items-start">
                <span className="text-green-500 mr-2">✓</span>
                Customer acquisition rate maintains at 15-20% monthly
              </li>
              <li className="flex items-start">
                <span className="text-green-500 mr-2">✓</span>
                Churn rate stays below 3% monthly
              </li>
              <li className="flex items-start">
                <span className="text-green-500 mr-2">✓</span>
                Average revenue per user increases by 5% quarterly
              </li>
              <li className="flex items-start">
                <span className="text-green-500 mr-2">✓</span>
                Expansion revenue contributes 20-25% of new revenue
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};

export const AnalyticsManagementPage: React.FC = () => {
  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'Analytics', icon: '📊' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">Analytics & Insights</h1>
        <p className="text-theme-secondary mt-1">
          Track performance metrics, generate reports, and forecast growth.
        </p>
      </div>

      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/analytics" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/analytics" />
      </div>

      <div>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard/analytics/overview" replace />} />
          <Route path="/overview" element={<AnalyticsPage />} />
          <Route path="/metrics" element={<MetricsPage />} />
          <Route path="/reports" element={<ReportsPage />} />
          <Route path="/revenue" element={<RevenuePage />} />
          <Route path="/customers" element={<CustomerAnalyticsPage />} />
          <Route path="/forecasting" element={<ForecastingPage />} />
        </Routes>
      </div>
    </div>
  );
};

export default AnalyticsManagementPage;