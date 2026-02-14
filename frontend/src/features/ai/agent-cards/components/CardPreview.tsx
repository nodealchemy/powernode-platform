import React from 'react';
import { CheckCircle, AlertCircle } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { cn } from '@/shared/utils/cn';

interface ValidationResult {
  valid: boolean;
  errors: string[];
}

interface CardPreviewProps {
  validationResult?: ValidationResult | null;
  streamingEnabled?: boolean;
  pushNotificationsEnabled?: boolean;
  authSchemes?: string[];
  onStreamingChange?: (enabled: boolean) => void;
  onPushNotificationsChange?: (enabled: boolean) => void;
  onAuthSchemeToggle?: (scheme: string) => void;
}

export const CardPreview: React.FC<CardPreviewProps> = ({
  validationResult,
  streamingEnabled,
  pushNotificationsEnabled,
  authSchemes,
  onStreamingChange,
  onPushNotificationsChange,
  onAuthSchemeToggle,
}) => (
  <>
    {validationResult && (
      <div className={cn(
        'p-4 rounded-lg border',
        validationResult.valid
          ? 'bg-theme-success/10 border-theme-success/30'
          : 'bg-theme-danger/10 border-theme-danger/30'
      )}>
        <div className={cn(
          'flex items-center gap-2',
          validationResult.valid ? 'text-theme-success' : 'text-theme-danger'
        )}>
          {validationResult.valid ? (
            <>
              <CheckCircle className="h-4 w-4" />
              <span className="font-medium">All validations passed</span>
            </>
          ) : (
            <>
              <AlertCircle className="h-4 w-4" />
              <span className="font-medium">Validation errors ({validationResult.errors.length})</span>
            </>
          )}
        </div>
        {validationResult.errors.length > 0 && (
          <ul className="mt-2 ml-6 list-disc text-sm text-theme-danger">
            {validationResult.errors.map((err, idx) => (
              <li key={idx}>{err}</li>
            ))}
          </ul>
        )}
      </div>
    )}

    {onStreamingChange && onPushNotificationsChange && onAuthSchemeToggle && (
      <Card>
        <CardHeader title="Advanced Options" />
        <CardContent className="space-y-4">
          <div className="flex items-center gap-6">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={streamingEnabled ?? false}
                onChange={(e) => onStreamingChange(e.target.checked)}
                className="rounded border-theme"
              />
              <span className="text-sm text-theme-primary">Enable Streaming</span>
            </label>

            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={pushNotificationsEnabled ?? false}
                onChange={(e) => onPushNotificationsChange(e.target.checked)}
                className="rounded border-theme"
              />
              <span className="text-sm text-theme-primary">Enable Push Notifications</span>
            </label>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Authentication Schemes
            </label>
            <div className="flex items-center gap-4">
              {['bearer', 'api_key', 'oauth2', 'none'].map((scheme) => (
                <label key={scheme} className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={(authSchemes ?? []).includes(scheme)}
                    onChange={() => onAuthSchemeToggle(scheme)}
                    className="rounded border-theme"
                  />
                  <span className="text-sm text-theme-primary capitalize">{scheme.replace('_', ' ')}</span>
                </label>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>
    )}
  </>
);
