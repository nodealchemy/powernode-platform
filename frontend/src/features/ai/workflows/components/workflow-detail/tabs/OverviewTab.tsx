import React from 'react';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Select } from '@/shared/components/ui/Select';
import { AiWorkflow } from '@/shared/types/workflow';
import { renderStatusBadge } from '../utils/workflowDetailUtils';

interface OverviewTabProps {
  workflow: AiWorkflow;
  isEditMode: boolean;
  editedWorkflow: Partial<AiWorkflow>;
  onEditChange: (updates: Partial<AiWorkflow>) => void;
}

export const OverviewTab: React.FC<OverviewTabProps> = ({
  workflow,
  isEditMode,
  editedWorkflow,
  onEditChange
}) => {
  return (
    <Card>
      <CardTitle>Basic Information</CardTitle>
      <CardContent className="space-y-4">
        <div>
          <label className="text-sm font-medium text-theme-muted block mb-2">Name</label>
          {isEditMode ? (
            <Input
              value={editedWorkflow.name || ''}
              onChange={(e) => onEditChange({ name: e.target.value })}
              placeholder="Workflow name"
            />
          ) : (
            <p className="text-theme-primary">{workflow.name}</p>
          )}
        </div>

        <div>
          <label className="text-sm font-medium text-theme-muted block mb-2">Description</label>
          {isEditMode ? (
            <Textarea
              value={editedWorkflow.description || ''}
              onChange={(e) => onEditChange({ description: e.target.value })}
              placeholder="Workflow description"
              rows={3}
            />
          ) : (
            <p className="text-theme-primary">{workflow.description}</p>
          )}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-sm font-medium text-theme-muted block mb-2">Status</label>
            {isEditMode ? (
              <Select
                value={editedWorkflow.status || workflow.status}
                onChange={(value) => onEditChange({ status: value as AiWorkflow['status'] })}
              >
                <option value="draft">Draft</option>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="archived">Archived</option>
                <option value="paused">Paused</option>
              </Select>
            ) : (
              <div className="mt-1">{renderStatusBadge(workflow.status)}</div>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-theme-muted block mb-2">Visibility</label>
            {isEditMode ? (
              <Select
                value={editedWorkflow.visibility || workflow.visibility}
                onChange={(value) => onEditChange({ visibility: value as AiWorkflow['visibility'] })}
              >
                <option value="private">Private</option>
                <option value="account">Account</option>
                <option value="public">Public</option>
              </Select>
            ) : (
              <p className="text-theme-primary capitalize">{workflow.visibility}</p>
            )}
          </div>
        </div>

        <div>
          <label className="text-sm font-medium text-theme-muted block mb-2">Tags</label>
          {isEditMode ? (
            <Input
              value={editedWorkflow.tags?.join(', ') || ''}
              onChange={(e) => onEditChange({
                tags: e.target.value.split(',').map(t => t.trim()).filter(Boolean)
              })}
              placeholder="Enter tags separated by commas"
            />
          ) : (
            <div className="flex flex-wrap gap-2">
              {workflow.tags && workflow.tags.length > 0 ? (
                workflow.tags.map(tag => (
                  <Badge key={tag} variant="outline">
                    {tag}
                  </Badge>
                ))
              ) : (
                <p className="text-theme-muted text-sm">No tags</p>
              )}
            </div>
          )}
        </div>

        {!isEditMode && (
          <>
            <div className="border-t border-theme pt-4">
              <label className="text-sm font-medium text-theme-muted">Created</label>
              <p className="mt-1 text-theme-primary">
                {workflow.created_at ? new Date(workflow.created_at).toLocaleDateString() : 'Unknown'} by{' '}
                {workflow.created_by?.name || 'Unknown User'}
              </p>
            </div>

            <div className="border-t border-theme pt-4">
              <label className="text-sm font-medium text-theme-muted">Statistics</label>
              <div className="grid grid-cols-2 gap-4 mt-2">
                <div>
                  <p className="text-sm text-theme-muted">Total Nodes</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {workflow.stats?.nodes_count || 0}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-theme-muted">Total Runs</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {workflow.stats?.runs_count || 0}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-theme-muted">Success Rate</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {workflow.stats?.success_rate ? `${Math.round(workflow.stats.success_rate * 100)}%` : 'N/A'}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-theme-muted">Avg Runtime</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {workflow.stats?.avg_runtime ? `${workflow.stats.avg_runtime}s` : 'N/A'}
                  </p>
                </div>
              </div>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
};
