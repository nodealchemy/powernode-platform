import React from 'react';
import { X, GitBranch, ArrowRight, ArrowLeft, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useKnowledgeNodeDetail } from '../api/knowledgeGraphApi';
import type { EntityType, RelationType } from '../types/knowledgeGraph';

interface NodeDetailPanelProps {
  nodeId: string | null;
  onClose: () => void;
  onNodeSelect: (nodeId: string) => void;
}

const ENTITY_TYPE_BADGE: Record<EntityType, 'info' | 'success' | 'warning' | 'danger' | 'default'> = {
  concept: 'info',
  entity: 'success',
  document: 'warning',
  agent: 'info',
  skill: 'default',
  context: 'danger',
  learning: 'success',
};

const RELATION_TYPE_BADGE: Record<RelationType, 'info' | 'success' | 'warning' | 'danger' | 'default'> = {
  related_to: 'default',
  depends_on: 'warning',
  derived_from: 'info',
  part_of: 'success',
  uses: 'info',
  produces: 'success',
  contradicts: 'danger',
  supports: 'success',
};

export const NodeDetailPanel: React.FC<NodeDetailPanelProps> = ({
  nodeId,
  onClose,
  onNodeSelect,
}) => {
  const { data: nodeDetail, isLoading } = useKnowledgeNodeDetail(nodeId || '', !!nodeId);

  if (!nodeId) return null;

  return (
    <div className="fixed inset-y-0 right-0 w-96 bg-theme-surface border-l border-theme shadow-xl z-50 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-theme">
        <h3 className="text-lg font-semibold text-theme-primary truncate">Node Details</h3>
        <button
          onClick={onClose}
          className="p-1 rounded-lg text-theme-tertiary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
        >
          <X className="h-5 w-5" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {isLoading ? (
          <LoadingSpinner size="sm" className="py-8" />
        ) : !nodeDetail ? (
          <div className="text-center py-8">
            <p className="text-theme-secondary">Node not found.</p>
          </div>
        ) : (
          <>
            {/* Node info */}
            <div>
              <h4 className="text-xl font-bold text-theme-primary">{nodeDetail.name}</h4>
              <div className="flex items-center gap-2 mt-2">
                <Badge variant={ENTITY_TYPE_BADGE[nodeDetail.entity_type]} size="xs">
                  {nodeDetail.entity_type}
                </Badge>
                <Badge variant={nodeDetail.status === 'active' ? 'success' : 'warning'} size="xs">
                  {nodeDetail.status}
                </Badge>
              </div>
              {nodeDetail.description && (
                <p className="text-sm text-theme-secondary mt-3">{nodeDetail.description}</p>
              )}
            </div>

            {/* Metadata */}
            <Card className="p-3">
              <div className="flex items-center gap-2 mb-2">
                <GitBranch className="h-4 w-4 text-theme-tertiary" />
                <span className="text-sm font-medium text-theme-primary">Connections</span>
              </div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>
                  <span className="text-theme-tertiary">Degree:</span>{' '}
                  <span className="font-medium text-theme-primary">{nodeDetail.degree ?? nodeDetail.mention_count}</span>
                </div>
                <div>
                  <span className="text-theme-tertiary">Neighbors:</span>{' '}
                  <span className="font-medium text-theme-primary">{nodeDetail.neighbors?.length ?? 0}</span>
                </div>
              </div>
            </Card>

            {/* Timestamps */}
            <Card className="p-3">
              <div className="flex items-center gap-2 mb-2">
                <Clock className="h-4 w-4 text-theme-tertiary" />
                <span className="text-sm font-medium text-theme-primary">Timestamps</span>
              </div>
              <div className="space-y-1 text-sm">
                <div>
                  <span className="text-theme-tertiary">Created:</span>{' '}
                  <span className="text-theme-secondary">{new Date(nodeDetail.created_at).toLocaleString()}</span>
                </div>
                {nodeDetail.last_seen_at && (
                  <div>
                    <span className="text-theme-tertiary">Last seen:</span>{' '}
                    <span className="text-theme-secondary">{new Date(nodeDetail.last_seen_at).toLocaleString()}</span>
                  </div>
                )}
                <div>
                  <span className="text-theme-tertiary">Confidence:</span>{' '}
                  <span className="text-theme-secondary">{(nodeDetail.confidence * 100).toFixed(0)}%</span>
                </div>
              </div>
            </Card>

            {/* Properties */}
            {nodeDetail.properties && Object.keys(nodeDetail.properties).length > 0 && (
              <Card className="p-3">
                <h4 className="text-sm font-medium text-theme-primary mb-2">Properties</h4>
                <div className="space-y-1">
                  {Object.entries(nodeDetail.properties).map(([key, value]) => (
                    <div key={key} className="flex items-start justify-between text-sm">
                      <span className="text-theme-tertiary">{key}</span>
                      <span className="text-theme-secondary text-right max-w-[60%] truncate">
                        {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                      </span>
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {/* Metadata */}
            {nodeDetail.metadata && Object.keys(nodeDetail.metadata).length > 0 && (
              <Card className="p-3">
                <h4 className="text-sm font-medium text-theme-primary mb-2">Metadata</h4>
                <div className="space-y-1">
                  {Object.entries(nodeDetail.metadata).map(([key, value]) => (
                    <div key={key} className="flex items-start justify-between text-sm">
                      <span className="text-theme-tertiary">{key}</span>
                      <span className="text-theme-secondary text-right max-w-[60%] truncate">
                        {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                      </span>
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {/* Outgoing Edges */}
            {(nodeDetail.outgoing_edges?.length ?? 0) > 0 && (
              <div>
                <h4 className="text-sm font-semibold text-theme-primary mb-2 flex items-center gap-1">
                  <ArrowRight className="h-4 w-4" />
                  Outgoing ({nodeDetail.outgoing_edges?.length})
                </h4>
                <div className="space-y-1">
                  {nodeDetail.outgoing_edges?.map((edge) => (
                    <button
                      key={edge.id}
                      onClick={() => onNodeSelect(edge.target_node_id)}
                      className="w-full text-left p-2 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors"
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-theme-primary truncate">{edge.target_name || edge.target_node_id}</span>
                        <Badge variant={RELATION_TYPE_BADGE[edge.relation_type]} size="xs">
                          {edge.relation_type.replace(/_/g, ' ')}
                        </Badge>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Incoming Edges */}
            {(nodeDetail.incoming_edges?.length ?? 0) > 0 && (
              <div>
                <h4 className="text-sm font-semibold text-theme-primary mb-2 flex items-center gap-1">
                  <ArrowLeft className="h-4 w-4" />
                  Incoming ({nodeDetail.incoming_edges?.length})
                </h4>
                <div className="space-y-1">
                  {nodeDetail.incoming_edges?.map((edge) => (
                    <button
                      key={edge.id}
                      onClick={() => onNodeSelect(edge.source_node_id)}
                      className="w-full text-left p-2 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors"
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-theme-primary truncate">{edge.source_name || edge.source_node_id}</span>
                        <Badge variant={RELATION_TYPE_BADGE[edge.relation_type]} size="xs">
                          {edge.relation_type.replace(/_/g, ' ')}
                        </Badge>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
};
