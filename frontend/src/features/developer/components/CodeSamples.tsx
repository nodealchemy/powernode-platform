import React, { useState } from 'react';
import { Card, Button } from '@/shared/components/ui';

type Language = 'curl' | 'javascript' | 'python' | 'ruby';

const SAMPLES: Record<string, Record<Language, string>> = {
  'list-subscriptions': {
    curl: `curl -X GET "https://api.powernode.io/api/v1/subscriptions" \\
     -H "Authorization: Bearer YOUR_JWT_TOKEN" \\
     -H "Content-Type: application/json"`,
    javascript: `const response = await fetch('https://api.powernode.io/api/v1/subscriptions', {
  method: 'GET',
  headers: {
    'Authorization': 'Bearer YOUR_JWT_TOKEN',
    'Content-Type': 'application/json'
  }
});

const data = await response.json();
console.log(data);`,
    python: `import requests

response = requests.get(
    'https://api.powernode.io/api/v1/subscriptions',
    headers={
        'Authorization': 'Bearer YOUR_JWT_TOKEN',
        'Content-Type': 'application/json'
    }
)

data = response.json()
print(data)`,
    ruby: `require 'net/http'
require 'json'

uri = URI('https://api.powernode.io/api/v1/subscriptions')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request['Authorization'] = 'Bearer YOUR_JWT_TOKEN'
request['Content-Type'] = 'application/json'

response = http.request(request)
data = JSON.parse(response.body)
puts data`,
  },
  'track-usage': {
    curl: `curl -X POST "https://api.powernode.io/api/v1/usage_events" \\
     -H "Authorization: Bearer YOUR_JWT_TOKEN" \\
     -H "Content-Type: application/json" \\
     -d '{
       "meter_slug": "api_calls",
       "quantity": 1,
       "event_id": "evt_unique_id_123",
       "properties": {
         "endpoint": "/api/users",
         "method": "GET"
       }
     }'`,
    javascript: `const response = await fetch('https://api.powernode.io/api/v1/usage_events', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_JWT_TOKEN',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    meter_slug: 'api_calls',
    quantity: 1,
    event_id: 'evt_unique_id_123',
    properties: {
      endpoint: '/api/users',
      method: 'GET'
    }
  })
});

const data = await response.json();
console.log(data);`,
    python: `import requests

response = requests.post(
    'https://api.powernode.io/api/v1/usage_events',
    headers={
        'Authorization': 'Bearer YOUR_JWT_TOKEN',
        'Content-Type': 'application/json'
    },
    json={
        'meter_slug': 'api_calls',
        'quantity': 1,
        'event_id': 'evt_unique_id_123',
        'properties': {
            'endpoint': '/api/users',
            'method': 'GET'
        }
    }
)

data = response.json()
print(data)`,
    ruby: `require 'net/http'
require 'json'

uri = URI('https://api.powernode.io/api/v1/usage_events')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri)
request['Authorization'] = 'Bearer YOUR_JWT_TOKEN'
request['Content-Type'] = 'application/json'
request.body = {
  meter_slug: 'api_calls',
  quantity: 1,
  event_id: 'evt_unique_id_123',
  properties: {
    endpoint: '/api/users',
    method: 'GET'
  }
}.to_json

response = http.request(request)
data = JSON.parse(response.body)
puts data`,
  },
  'create-webhook': {
    curl: `curl -X POST "https://api.powernode.io/api/v1/webhooks" \\
     -H "Authorization: Bearer YOUR_JWT_TOKEN" \\
     -H "Content-Type: application/json" \\
     -d '{
       "url": "https://your-server.com/webhooks/powernode",
       "event_types": ["subscription.created", "payment.completed"],
       "description": "Production webhook endpoint"
     }'`,
    javascript: `const response = await fetch('https://api.powernode.io/api/v1/webhooks', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_JWT_TOKEN',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    url: 'https://your-server.com/webhooks/powernode',
    event_types: ['subscription.created', 'payment.completed'],
    description: 'Production webhook endpoint'
  })
});

const data = await response.json();
console.log(data);`,
    python: `import requests

response = requests.post(
    'https://api.powernode.io/api/v1/webhooks',
    headers={
        'Authorization': 'Bearer YOUR_JWT_TOKEN',
        'Content-Type': 'application/json'
    },
    json={
        'url': 'https://your-server.com/webhooks/powernode',
        'event_types': ['subscription.created', 'payment.completed'],
        'description': 'Production webhook endpoint'
    }
)

data = response.json()
print(data)`,
    ruby: `require 'net/http'
require 'json'

uri = URI('https://api.powernode.io/api/v1/webhooks')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri)
request['Authorization'] = 'Bearer YOUR_JWT_TOKEN'
request['Content-Type'] = 'application/json'
request.body = {
  url: 'https://your-server.com/webhooks/powernode',
  event_types: ['subscription.created', 'payment.completed'],
  description: 'Production webhook endpoint'
}.to_json

response = http.request(request)
data = JSON.parse(response.body)
puts data`,
  },
};

export const CodeSamples: React.FC = () => {
  const [selectedLanguage, setSelectedLanguage] = useState<Language>('javascript');
  const [copiedSample, setCopiedSample] = useState<string | null>(null);

  const languages: { id: Language; label: string }[] = [
    { id: 'curl', label: 'cURL' },
    { id: 'javascript', label: 'JavaScript' },
    { id: 'python', label: 'Python' },
    { id: 'ruby', label: 'Ruby' },
  ];

  const samples = [
    { id: 'list-subscriptions', title: 'List Subscriptions', description: 'Retrieve a list of all subscriptions' },
    { id: 'track-usage', title: 'Track Usage Event', description: 'Send a usage event for metering' },
    { id: 'create-webhook', title: 'Create Webhook', description: 'Register a new webhook endpoint' },
  ];

  const handleCopy = async (sampleId: string, code: string) => {
    await navigator.clipboard.writeText(code);
    setCopiedSample(sampleId);
    setTimeout(() => setCopiedSample(null), 2000);
  };

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Code Samples</h3>
            <p className="text-sm text-theme-tertiary">Ready-to-use code snippets for common operations</p>
          </div>
          <div className="flex gap-2">
            {languages.map((lang) => (
              <Button
                key={lang.id}
                variant={selectedLanguage === lang.id ? 'primary' : 'secondary'}
                size="sm"
                onClick={() => setSelectedLanguage(lang.id)}
              >
                {lang.label}
              </Button>
            ))}
          </div>
        </div>

        <div className="space-y-6">
          {samples.map((sample) => (
            <div key={sample.id} className="border border-theme rounded-lg overflow-hidden">
              <div className="flex items-center justify-between p-4 bg-theme-surface border-b border-theme">
                <div>
                  <h4 className="font-medium text-theme-primary">{sample.title}</h4>
                  <p className="text-sm text-theme-tertiary">{sample.description}</p>
                </div>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => handleCopy(sample.id, SAMPLES[sample.id][selectedLanguage])}
                >
                  {copiedSample === sample.id ? 'Copied!' : 'Copy'}
                </Button>
              </div>
              <pre className="p-4 overflow-x-auto text-sm bg-theme-background">
                <code className="text-theme-inverse">{SAMPLES[sample.id][selectedLanguage]}</code>
              </pre>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};
