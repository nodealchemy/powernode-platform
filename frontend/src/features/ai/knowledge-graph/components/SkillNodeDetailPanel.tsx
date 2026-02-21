import React, { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { X, ArrowRight, ArrowLeft, Wrench, Terminal, Server, BarChart3 } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { SKILL_EDGE_DISPLAY } from '../types/skillGraph';
import type { SkillGraphResult, SkillEdgeRelation } from '../types/skillGraph';

interface SkillNodeDetailPanelProps {
  nodeId: string | null;
  graphData: SkillGraphResult;
  onClose: () => void;
  onNodeSelect: (nodeId: string) => void;
  onViewSkill?: (skillId: string) => void;
}

const RELATION_BADGE_VARIANT: Record<SkillEdgeRelation, 'warning' | 'info' | 'success' | 'default'> = {
  requires: 'warning',
  enhances: 'info',
  composes: 'success',
  succeeds: 'default',
};

export const SkillNodeDetailPanel: React.FC<SkillNodeDetailPanelProps> = ({
  nodeId,
  graphData,
  onClose,
  onNodeSelect,
  onViewSkill,
}) => {
  const navigate = useNavigate();

  const node = useMemo(
    () => graphData.nodes.find(n => n.id === nodeId),
    [graphData.nodes, nodeId]
  );

  const outgoingEdges = useMemo(
    () => graphData.edges.filter(e => e.source_skill_id === nodeId),
    [graphData.edges, nodeId]
  );

  const incomingEdges = useMemo(
    () => graphData.edges.filter(e => e.target_skill_id === nodeId),
    [graphData.edges, nodeId]
  );

  const requiresOut = outgoingEdges.filter(e => e.relation_type === 'requires');
  const requiredByIn = incomingEdges.filter(e => e.relation_type === 'requires');
  const otherOut = outgoingEdges.filter(e => e.relation_type !== 'requires');
  const otherIn = incomingEdges.filter(e => e.relation_type !== 'requires');

  if (!nodeId || !node) return null;

  return (
    <div className="fixed inset-y-0 right-0 w-96 bg-theme-surface border-l border-theme shadow-xl z-50 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-theme">
        <div className="min-w-0">
          <h3 className="text-lg font-semibold text-theme-primary truncate">{node.name}</h3>
          <div className="flex items-center gap-2 mt-1">
            <Badge variant="default" size="xs">{node.category.replace(/_/g, ' ')}</Badge>
            <Badge variant={node.status === 'active' ? 'success' : 'warning'} size="xs">{node.status}</Badge>
          </div>
        </div>
        <button
          onClick={onClose}
          className="p-1 rounded-lg text-theme-tertiary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
        >
          <X className="h-5 w-5" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Stats Grid */}
        <div className="grid grid-cols-3 gap-2">
          <Card className="p-3 text-center">
            <Terminal className="h-4 w-4 text-theme-info mx-auto mb-1" />
            <div className="text-lg font-semibold text-theme-primary">{node.command_count}</div>
            <div className="text-[10px] text-theme-tertiary">Commands</div>
          </Card>
          <Card className="p-3 text-center">
            <Server className="h-4 w-4 text-theme-success mx-auto mb-1" />
            <div className="text-lg font-semibold text-theme-primary">{node.connector_count}</div>
            <div className="text-[10px] text-theme-tertiary">MCP Servers</div>
          </Card>
          <Card className="p-3 text-center">
            <BarChart3 className="h-4 w-4 text-theme-warning mx-auto mb-1" />
            <div className="text-lg font-semibold text-theme-primary">{node.dependency_count}</div>
            <div className="text-[10px] text-theme-tertiary">Dependencies</div>
          </Card>
        </div>

        {/* Requires (outgoing) */}
        {requiresOut.length > 0 && (
          <div>
            <h4 className="text-sm font-semibold text-theme-primary mb-2 flex items-center gap-1">
              <ArrowRight className="h-4 w-4" />
              Requires ({requiresOut.length})
            </h4>
            <div className="space-y-1">
              {requiresOut.map(edge => (
                <button
                  key={edge.id}
                  onClick={() => onNodeSelect(edge.target_skill_id)}
                  className="w-full text-left p-2 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-theme-primary truncate">{edge.target_skill_name || edge.target_skill_id}</span>
                    <Badge variant="warning" size="xs">requires</Badge>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Required By (incoming) */}
        {requiredByIn.length > 0 && (
          <div>
            <h4 className="text-sm font-semibold text-theme-primary mb-2 flex items-center gap-1">
              <ArrowLeft className="h-4 w-4" />
              Required By ({requiredByIn.length})
            </h4>
            <div className="space-y-1">
              {requiredByIn.map(edge => (
                <button
                  key={edge.id}
                  onClick={() => onNodeSelect(edge.source_skill_id)}
                  className="w-full text-left p-2 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-theme-primary truncate">{edge.source_skill_name || edge.source_skill_id}</span>
                    <Badge variant="warning" size="xs">required by</Badge>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Other Connections */}
        {(otherOut.length > 0 || otherIn.length > 0) && (
          <div>
            <h4 className="text-sm font-semibold text-theme-primary mb-2">
              Other Connections ({otherOut.length + otherIn.length})
            </h4>
            <div className="space-y-1">
              {otherOut.map(edge => (
                <button
                  key={edge.id}
                  onClick={() => onNodeSelect(edge.target_skill_id)}
                  className="w-full text-left p-2 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-theme-primary truncate">{edge.target_skill_name || edge.target_skill_id}</span>
                    <Badge variant={RELATION_BADGE_VARIANT[edge.relation_type] || 'default'} size="xs">
                      {SKILL_EDGE_DISPLAY[edge.relation_type]?.label || edge.relation_type}
                    </Badge>
                  </div>
                </button>
              ))}
              {otherIn.map(edge => (
                <button
                  key={edge.id}
                  onClick={() => onNodeSelect(edge.source_skill_id)}
                  className="w-full text-left p-2 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-theme-primary truncate">{edge.source_skill_name || edge.source_skill_id}</span>
                    <Badge variant={RELATION_BADGE_VARIANT[edge.relation_type] || 'default'} size="xs">
                      {SKILL_EDGE_DISPLAY[edge.relation_type]?.label || edge.relation_type} (in)
                    </Badge>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* View Full Skill */}
        <div className="pt-2">
          <Button
            variant="secondary"
            size="sm"
            className="w-full"
            onClick={() => {
              if (onViewSkill && node.skill_id) {
                onViewSkill(node.skill_id);
              } else {
                navigate('/app/ai/knowledge/skills');
              }
            }}
          >
            <Wrench className="h-3.5 w-3.5 mr-1.5" />
            View Full Skill
          </Button>
        </div>
      </div>
    </div>
  );
};
