import React from 'react';
import { Input } from '@/shared/components/ui/Input';

interface WebSocketConfigFieldsProps {
  url: string;
  onUrlChange: (value: string) => void;
  urlError?: string;
  connectionType: 'websocket' | 'http';
}

export const WebSocketConfigFields: React.FC<WebSocketConfigFieldsProps> = ({
  url,
  onUrlChange,
  urlError,
  connectionType,
}) => (
  <div>
    <label className="block text-sm font-medium text-theme-primary mb-1">
      URL *
    </label>
    <Input
      type="text"
      value={url}
      onChange={(e) => onUrlChange(e.target.value)}
      placeholder={
        connectionType === 'websocket'
          ? 'e.g., wss://mcp.example.com'
          : 'e.g., http://localhost:3100'
      }
      className={urlError ? 'border-theme-error' : ''}
    />
    {urlError && (
      <p className="mt-1 text-sm text-theme-error">{urlError}</p>
    )}
  </div>
);
