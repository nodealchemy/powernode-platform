import React, { useState } from 'react';
import { PageContainer } from '@/shared/components/layout';
import { Card, TabContainer } from '@/shared/components/ui';
import { ApiDocs } from './ApiDocs';
import { CodeSamples } from '../components/CodeSamples';
import { ApiKeyManager } from '../components/ApiKeyManager';

export const DeveloperPortal: React.FC = () => {
  const [activeTab, setActiveTab] = useState('docs');

  const tabs = [
    { id: 'docs', label: 'API Documentation' },
    { id: 'keys', label: 'API Keys' },
    { id: 'samples', label: 'Code Samples' },
    { id: 'webhooks', label: 'Webhooks' },
  ];

  return (
    <PageContainer
      title="Developer Portal"
      description="Integrate with the Powernode API to build powerful subscription management solutions."
    >
      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6 mb-6">
        <Card className="p-6">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 rounded-lg bg-blue-100 flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            </div>
            <div>
              <p className="font-semibold text-theme-primary">REST API</p>
              <p className="text-sm text-theme-tertiary">OpenAPI 3.0</p>
            </div>
          </div>
          <a
            href="/api-docs"
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm text-blue-600 hover:text-blue-700"
          >
            View Interactive Docs →
          </a>
        </Card>

        <Card className="p-6">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 rounded-lg bg-green-100 flex items-center justify-center">
              <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
              </svg>
            </div>
            <div>
              <p className="font-semibold text-theme-primary">Authentication</p>
              <p className="text-sm text-theme-tertiary">JWT & API Keys</p>
            </div>
          </div>
          <span className="text-sm text-theme-tertiary">Bearer token or X-API-Key header</span>
        </Card>

        <Card className="p-6">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 rounded-lg bg-purple-100 flex items-center justify-center">
              <svg className="w-5 h-5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <div>
              <p className="font-semibold text-theme-primary">Webhooks</p>
              <p className="text-sm text-theme-tertiary">Real-time events</p>
            </div>
          </div>
          <span className="text-sm text-theme-tertiary">HMAC-SHA256 signatures</span>
        </Card>

        <Card className="p-6">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 rounded-lg bg-amber-100 flex items-center justify-center">
              <svg className="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <div>
              <p className="font-semibold text-theme-primary">Rate Limits</p>
              <p className="text-sm text-theme-tertiary">Fair usage policy</p>
            </div>
          </div>
          <span className="text-sm text-theme-tertiary">1000 req/min per API key</span>
        </Card>
      </div>

      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
      >
        {activeTab === 'docs' && <ApiDocs />}
        {activeTab === 'keys' && <ApiKeyManager />}
        {activeTab === 'samples' && <CodeSamples />}
        {activeTab === 'webhooks' && <WebhookDocs />}
      </TabContainer>
    </PageContainer>
  );
};

const WebhookDocs: React.FC = () => {
  const events = [
    { name: 'subscription.created', description: 'Fired when a new subscription is created' },
    { name: 'subscription.updated', description: 'Fired when a subscription is updated' },
    { name: 'subscription.cancelled', description: 'Fired when a subscription is cancelled' },
    { name: 'payment.completed', description: 'Fired when a payment is successfully processed' },
    { name: 'payment.failed', description: 'Fired when a payment fails' },
    { name: 'invoice.created', description: 'Fired when a new invoice is generated' },
    { name: 'invoice.paid', description: 'Fired when an invoice is paid' },
    { name: 'user.created', description: 'Fired when a new user is created' },
  ];

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Webhook Events</h3>
        <p className="text-theme-secondary mb-6">
          Webhooks allow you to receive real-time notifications about events in your Powernode account.
          Configure webhook endpoints in your account settings to receive these events.
        </p>

        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-theme">
                <th className="text-left py-3 px-2 text-sm font-medium text-theme-secondary">Event</th>
                <th className="text-left py-3 px-2 text-sm font-medium text-theme-secondary">Description</th>
              </tr>
            </thead>
            <tbody>
              {events.map((event) => (
                <tr key={event.name} className="border-b border-theme">
                  <td className="py-3 px-2">
                    <code className="text-sm bg-theme-surface px-2 py-1 rounded font-mono text-blue-600">
                      {event.name}
                    </code>
                  </td>
                  <td className="py-3 px-2 text-sm text-theme-secondary">{event.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Verifying Webhook Signatures</h3>
        <p className="text-theme-secondary mb-4">
          All webhook requests include a signature in the <code className="bg-theme-surface px-1 rounded">X-Webhook-Signature</code> header.
          Verify this signature to ensure the request came from Powernode.
        </p>

        <pre className="bg-theme-surface p-4 rounded-lg overflow-x-auto text-sm">
          <code className="text-theme-primary">{`// Node.js signature verification
const crypto = require('crypto');

function verifySignature(payload, signature, secret) {
  const [timestamp, sig] = signature.split(',').reduce((acc, part) => {
    const [key, value] = part.split('=');
    acc[key === 't' ? 0 : 1] = value;
    return acc;
  }, [null, null]);

  // Verify timestamp is within 5 minutes
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - parseInt(timestamp)) > 300) {
    return false;
  }

  const expectedSig = crypto
    .createHmac('sha256', secret)
    .update(\`\${timestamp}.\${JSON.stringify(payload)}\`)
    .digest('hex');

  return crypto.timingSafeEqual(
    Buffer.from(sig),
    Buffer.from(expectedSig)
  );
}`}</code>
        </pre>
      </Card>
    </div>
  );
};
