import React, { useState } from 'react';
import { GitBranch, User, ChevronRight, ChevronDown } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { EntityLink } from '@/shared/components/entity';
import { cn } from '@/shared/utils/cn';
import type { AgentLineageNode } from '../types/autonomy';

const TRUST_LEVEL_VARIANT: Record<string, 'warning' | 'info' | 'success' | 'default' | 'outline'> = {
  supervised: 'warning',
  monitored: 'info',
  trusted: 'success',
  autonomous: 'default',
};

const STATUS_VARIANT: Record<string, 'success' | 'secondary' | 'danger' | 'outline'> = {
  active: 'success',
  inactive: 'secondary',
  paused: 'secondary',
  error: 'danger',
};

interface LineageNodeProps {
  node: AgentLineageNode;
  depth?: number;
}

const LineageNode: React.FC<LineageNodeProps> = ({ node, depth = 0 }) => {
  const [expanded, setExpanded] = useState(depth < 2);
  const children = node.children ?? [];
  const hasChildren = children.length > 0;

  return (
    <div>
      <div
        data-testid={`lineage-node-${node.id}`}
        className={cn(
          'flex items-center gap-2 py-2 px-3 rounded-lg hover:bg-theme-surface-hover transition-colors',
          hasChildren && 'cursor-pointer'
        )}
        style={{ paddingLeft: `${depth * 24 + 12}px` }}
        onClick={() => hasChildren && setExpanded(!expanded)}
      >
        {hasChildren ? (
          expanded ? (
            <ChevronDown className="h-4 w-4 text-theme-secondary shrink-0" />
          ) : (
            <ChevronRight className="h-4 w-4 text-theme-secondary shrink-0" />
          )
        ) : (
          <span className="w-4 shrink-0" />
        )}

        <div className="h-7 w-7 rounded-md bg-theme-info-fg/10 flex items-center justify-center shrink-0">
          {depth === 0 ? (
            <GitBranch className="h-4 w-4 text-theme-info-fg" />
          ) : (
            <User className="h-4 w-4 text-theme-info-fg" />
          )}
        </div>

        {/* Name FIRST; agent_type is a secondary label. Several distinct agents share
            one type (seven carry data_analyst), so a type-led label reads as duplicates. */}
        <div className="flex-1 min-w-0 flex items-center gap-2">
          <span data-testid="lineage-node-name" className="min-w-0 truncate">
            <EntityLink type="agent" id={node.id} label={node.name} className="text-sm font-medium truncate" />
          </span>
          <span data-testid="lineage-node-type" className="text-xs text-theme-secondary shrink-0">
            {node.type}
          </span>
          {node.canonical && (
            <span className="shrink-0" title="Global seeded platform agent (read-only; clone to customize)">
              <Badge variant="outline" size="sm">canonical</Badge>
            </span>
          )}
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          <Badge variant={STATUS_VARIANT[node.status] || 'outline'} size="sm">
            {node.status}
          </Badge>
          {node.trust_level && (
            <Badge variant={TRUST_LEVEL_VARIANT[node.trust_level] || 'outline'} size="sm">
              {node.trust_level}
            </Badge>
          )}
        </div>
      </div>

      {expanded && hasChildren && (
        <div>
          {children.map((child) => (
            <LineageNode key={child.id} node={child} depth={depth + 1} />
          ))}
        </div>
      )}
    </div>
  );
};

interface AgentLineageTreeProps {
  root: AgentLineageNode;
}

export const AgentLineageTree: React.FC<AgentLineageTreeProps> = ({ root }) => {
  return (
    <div className="rounded-lg border border-theme bg-theme-surface divide-y divide-theme">
      <LineageNode node={root} />
    </div>
  );
};
