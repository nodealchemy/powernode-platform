import React from 'react';
import { Play, CheckCircle, Clock, GitBranch } from 'lucide-react';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { AiWorkflow } from '@/shared/types/workflow';
import { sortNodesInExecutionOrder, formatNodeType, getNodeExecutionLevels } from '@/shared/utils/workflow';

interface NodesTabProps {
  workflow: AiWorkflow;
}

export const NodesTab: React.FC<NodesTabProps> = ({ workflow }) => {
  return (
    <Card>
      <CardTitle>Workflow Nodes (Execution Order)</CardTitle>
      <CardContent>
        {workflow.nodes && workflow.nodes.length > 0 ? (
          <div className="space-y-3">
            {(() => {
              const sortedNodes = sortNodesInExecutionOrder(workflow.nodes, workflow.edges);
              const executionLevels = getNodeExecutionLevels(workflow.nodes, workflow.edges);

              return sortedNodes.map((node, index) => {
                const isLast = index === sortedNodes.length - 1;
                const executionLevel = executionLevels.get(node.node_id) || 0;

                return (
                  <div key={node.id} className="relative">
                    {!isLast && (
                      <div className="absolute left-6 top-12 bottom-0 w-0.5 bg-theme-border" />
                    )}

                    <div className="flex items-start gap-3">
                      <div className="flex flex-col items-center">
                        <div className={`
                          flex items-center justify-center w-12 h-12 rounded-full font-semibold text-sm
                          ${node.is_start_node ? 'bg-theme-success text-white' :
                            node.is_end_node ? 'bg-theme-info text-white' :
                            'bg-theme-surface border-2 border-theme text-theme-primary'}
                        `}>
                          {node.is_start_node ? (
                            <Play className="h-5 w-5" />
                          ) : node.is_end_node ? (
                            <CheckCircle className="h-5 w-5" />
                          ) : (
                            index + 1
                          )}
                        </div>
                      </div>

                      <div className="flex-1 p-4 border border-theme rounded-lg bg-theme-surface">
                        <div className="flex items-start justify-between gap-4">
                          <div className="flex-1">
                            <div className="flex items-center gap-2">
                              <h4 className="font-medium text-theme-primary">{node.name}</h4>
                              {node.is_start_node && (
                                <Badge variant="success" size="sm">Start</Badge>
                              )}
                              {node.is_end_node && (
                                <Badge variant="info" size="sm">End</Badge>
                              )}
                              {node.is_error_handler && (
                                <Badge variant="danger" size="sm">Error Handler</Badge>
                              )}
                            </div>

                            <div className="flex items-center gap-4 mt-2 text-sm text-theme-muted">
                              <span className="flex items-center gap-1">
                                <GitBranch className="h-3 w-3" />
                                Type: {formatNodeType(node.node_type || 'unknown')}
                              </span>
                              {executionLevel > 0 && (
                                <span className="flex items-center gap-1">
                                  Level: {executionLevel}
                                </span>
                              )}
                            </div>

                            {node.description && (
                              <p className="text-sm text-theme-secondary mt-2">{node.description}</p>
                            )}

                            {workflow.edges && (() => {
                              const outgoingEdges = workflow.edges.filter(e => e.source_node_id === node.node_id);
                              const incomingEdges = workflow.edges.filter(e => e.target_node_id === node.node_id);

                              return (outgoingEdges.length > 0 || incomingEdges.length > 0) && (
                                <div className="flex gap-4 mt-3 text-xs text-theme-muted">
                                  {incomingEdges.length > 0 && (
                                    <span>← {incomingEdges.length} input{incomingEdges.length > 1 ? 's' : ''}</span>
                                  )}
                                  {outgoingEdges.length > 0 && (
                                    <span>→ {outgoingEdges.length} output{outgoingEdges.length > 1 ? 's' : ''}</span>
                                  )}
                                </div>
                              );
                            })()}

                            {node.timeout_seconds && (
                              <div className="mt-2 text-xs text-theme-muted">
                                <Clock className="inline h-3 w-3 mr-1" />
                                Timeout: {node.timeout_seconds}s
                              </div>
                            )}
                            {node.retry_count && node.retry_count > 0 && (
                              <div className="mt-1 text-xs text-theme-muted">
                                Retry: {node.retry_count} time{node.retry_count > 1 ? 's' : ''}
                              </div>
                            )}
                          </div>

                          <div className="flex flex-col items-end gap-2">
                            <Badge
                              variant={
                                node.node_type === 'ai_agent' ? 'info' :
                                node.node_type === 'api_call' ? 'warning' :
                                node.node_type === 'human_approval' ? 'danger' :
                                'outline'
                              }
                              size="sm"
                            >
                              {node.node_type || 'unknown'}
                            </Badge>

                            <span className="text-xs text-theme-muted">
                              #{index + 1} of {sortedNodes.length}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              });
            })()}
          </div>
        ) : (
          <p className="text-theme-muted">No nodes configured for this workflow.</p>
        )}
      </CardContent>
    </Card>
  );
};
