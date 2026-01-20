import React from 'react';
import { Card } from '@/shared/components/ui';

export const ApiDocs: React.FC = () => {
  const endpoints = [
    {
      category: 'Authentication',
      routes: [
        { method: 'POST', path: '/api/v1/auth/login', description: 'Authenticate user and get JWT token' },
        { method: 'POST', path: '/api/v1/auth/logout', description: 'Invalidate current session' },
        { method: 'POST', path: '/api/v1/auth/refresh', description: 'Refresh JWT token' },
      ],
    },
    {
      category: 'Subscriptions',
      routes: [
        { method: 'GET', path: '/api/v1/subscriptions', description: 'List all subscriptions' },
        { method: 'GET', path: '/api/v1/subscriptions/:id', description: 'Get subscription details' },
        { method: 'POST', path: '/api/v1/subscriptions', description: 'Create a new subscription' },
        { method: 'PATCH', path: '/api/v1/subscriptions/:id', description: 'Update a subscription' },
        { method: 'DELETE', path: '/api/v1/subscriptions/:id', description: 'Cancel a subscription' },
      ],
    },
    {
      category: 'Usage Tracking',
      routes: [
        { method: 'GET', path: '/api/v1/usage/dashboard', description: 'Get usage dashboard data' },
        { method: 'POST', path: '/api/v1/usage_events', description: 'Track a usage event' },
        { method: 'POST', path: '/api/v1/usage_events/batch', description: 'Track multiple events (batch)' },
        { method: 'GET', path: '/api/v1/usage/meters', description: 'List available usage meters' },
        { method: 'GET', path: '/api/v1/usage/quotas', description: 'Get current quota status' },
      ],
    },
    {
      category: 'Billing',
      routes: [
        { method: 'GET', path: '/api/v1/invoices', description: 'List invoices' },
        { method: 'GET', path: '/api/v1/invoices/:id', description: 'Get invoice details' },
        { method: 'GET', path: '/api/v1/payments', description: 'List payments' },
        { method: 'GET', path: '/api/v1/payment_methods', description: 'List payment methods' },
      ],
    },
    {
      category: 'Analytics',
      routes: [
        { method: 'GET', path: '/api/v1/analytics/revenue', description: 'Get revenue analytics' },
        { method: 'GET', path: '/api/v1/analytics/growth', description: 'Get growth metrics' },
        { method: 'GET', path: '/api/v1/analytics/churn', description: 'Get churn analytics' },
        { method: 'GET', path: '/api/v1/analytics/cohorts', description: 'Get cohort analysis' },
      ],
    },
    {
      category: 'Webhooks',
      routes: [
        { method: 'GET', path: '/api/v1/webhooks', description: 'List webhook endpoints' },
        { method: 'POST', path: '/api/v1/webhooks', description: 'Create a webhook endpoint' },
        { method: 'PATCH', path: '/api/v1/webhooks/:id', description: 'Update a webhook endpoint' },
        { method: 'DELETE', path: '/api/v1/webhooks/:id', description: 'Delete a webhook endpoint' },
        { method: 'POST', path: '/api/v1/webhooks/:id/test', description: 'Send a test webhook' },
      ],
    },
  ];

  const getMethodColor = (method: string) => {
    switch (method) {
      case 'GET': return 'bg-blue-100 text-blue-700';
      case 'POST': return 'bg-green-100 text-green-700';
      case 'PATCH': return 'bg-amber-100 text-amber-700';
      case 'PUT': return 'bg-amber-100 text-amber-700';
      case 'DELETE': return 'bg-red-100 text-red-700';
      default: return 'bg-gray-100 text-gray-700';
    }
  };

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Interactive API Documentation</h3>
        <p className="text-theme-secondary mb-4">
          Explore our API using the interactive Swagger UI documentation. You can test endpoints directly from the browser.
        </p>
        <a
          href="/api-docs"
          target="_blank"
          rel="noopener noreferrer"
          className="btn-theme btn-theme-primary btn-theme-md inline-flex items-center gap-2"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
          </svg>
          Open Swagger UI
        </a>
      </Card>

      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Base URL</h3>
        <code className="block bg-theme-surface p-3 rounded-lg text-sm font-mono text-theme-primary">
          https://api.powernode.io/api/v1
        </code>
      </Card>

      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Authentication</h3>
        <p className="text-theme-secondary mb-4">
          All API requests require authentication. Include your API key in the header:
        </p>
        <pre className="bg-theme-surface p-4 rounded-lg overflow-x-auto text-sm">
          <code className="text-theme-primary">{`curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \\
     -H "Content-Type: application/json" \\
     https://api.powernode.io/api/v1/subscriptions

# Or using API Key
curl -H "X-API-Key: YOUR_API_KEY" \\
     -H "Content-Type: application/json" \\
     https://api.powernode.io/api/v1/subscriptions`}</code>
        </pre>
      </Card>

      {endpoints.map((category) => (
        <Card key={category.category} className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">{category.category}</h3>
          <div className="space-y-3">
            {category.routes.map((route, index) => (
              <div
                key={index}
                className="flex items-center gap-4 p-3 rounded-lg bg-theme-surface hover:bg-theme-hover transition-colors"
              >
                <span className={`px-2 py-1 text-xs font-bold rounded ${getMethodColor(route.method)}`}>
                  {route.method}
                </span>
                <code className="font-mono text-sm text-theme-primary flex-1">{route.path}</code>
                <span className="text-sm text-theme-tertiary">{route.description}</span>
              </div>
            ))}
          </div>
        </Card>
      ))}
    </div>
  );
};
