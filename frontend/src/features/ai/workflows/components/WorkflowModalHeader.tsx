import React from 'react';
import {
  Eye,
  Calendar,
  Settings,
  Wifi,
  WifiOff,
  BarChart3,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { AiWorkflow } from '@/shared/types/workflow';
import { renderStatusBadge, renderVisibilityBadge } from './workflow-detail';

interface WorkflowModalHeaderProps {
  workflow: AiWorkflow;
  isConnected: boolean;
  lastUpdateTime: Date;
}

export const WorkflowModalHeader: React.FC<WorkflowModalHeaderProps> = ({
  workflow,
  isConnected,
  lastUpdateTime,
}) => {
  return (
    <>
      {/* Title */}
      <div className="flex items-center gap-3">
        <span>{workflow.name}</span>
        <div className="flex items-center gap-1">
          {isConnected ? (
            <Wifi className="h-4 w-4 text-theme-success" aria-label="Live updates active" />
          ) : (
            <WifiOff className="h-4 w-4 text-theme-muted" aria-label="Live updates inactive" />
          )}
          <span className="text-xs text-theme-muted">
            {isConnected ? 'Live' : 'Offline'}
          </span>
        </div>
      </div>

      {/* Subtitle */}
      <div className="flex items-center justify-between">
        <span>{workflow.description}</span>
        <span className="text-xs text-theme-muted ml-4">
          Last updated: {lastUpdateTime.toLocaleTimeString()}
        </span>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Status</p>
                {renderStatusBadge(workflow.status)}
              </div>
              <Settings className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Visibility</p>
                {renderVisibilityBadge(workflow.visibility)}
              </div>
              <Eye className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Total Runs</p>
                <p className="text-lg font-semibold text-theme-primary">
                  {workflow.stats?.runs_count || 0}
                </p>
              </div>
              <BarChart3 className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Version</p>
                <p className="text-lg font-semibold text-theme-primary">v{workflow.version}</p>
              </div>
              <Calendar className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>
      </div>
    </>
  );
};
