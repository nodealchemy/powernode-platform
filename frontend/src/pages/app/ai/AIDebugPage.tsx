import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { AIPermissionsDebug } from '@/shared/components/ai/AIPermissionsDebug';

export const AIDebugPage: React.FC = () => {
  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  return (
    <PageContainer
      title="AI Authentication Debug"
      description="Diagnostic information for AI feature authentication and permissions"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI Orchestration', href: '/app/ai' },
        { label: 'Debug' }
      ]}
    >
      <div className="max-w-4xl">
        <AIPermissionsDebug />
        
        <div className="mt-6 p-4 bg-theme-info bg-opacity-5 border border-theme-info rounded-lg">
          <h4 className="font-medium text-theme-info mb-2">Troubleshooting Steps</h4>
          <ol className="list-decimal list-inside space-y-2 text-sm text-theme-tertiary">
            <li>If "Not Authenticated": Click "Refresh Session" or reload the page</li>
            <li>If "No Access Token": Clear browser storage and sign in again</li>
            <li>If "No AI Permissions": Contact your system administrator to grant AI access</li>
            <li>If you see 401 errors: Try refreshing the page or clearing browser cache</li>
            <li>For persistent issues: Copy the debug info and contact support</li>
          </ol>
        </div>

        <div className="mt-6 p-4 bg-theme-surface rounded-lg">
          <h4 className="font-medium text-theme-secondary mb-2">Common Solutions</h4>
          <div className="space-y-3 text-sm">
            <div>
              <strong className="text-theme-primary">Token Refresh Issues:</strong>
              <p className="text-theme-tertiary mt-1">
                If you're getting 401 errors, your session may have expired. The system should automatically 
                attempt to refresh your token, but you can also try manually refreshing or signing out and back in.
              </p>
            </div>
            <div>
              <strong className="text-theme-primary">Permission Issues:</strong>
              <p className="text-theme-tertiary mt-1">
                AI features require specific permissions like <code className="bg-theme-surface-elevated px-1 rounded">ai.providers.read</code>. 
                System admins need to assign appropriate roles that include these permissions.
              </p>
            </div>
            <div>
              <strong className="text-theme-primary">Browser Issues:</strong>
              <p className="text-theme-tertiary mt-1">
                Clear browser cache/cookies, disable browser extensions, or try an incognito window 
                to rule out browser-related issues.
              </p>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};