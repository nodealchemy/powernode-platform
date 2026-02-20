import { AlertTriangle, Database, Globe, Link, Server } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import type { ResearchReport } from '../types/lifecycle';

interface ResearchResultsPanelProps {
  report: ResearchReport;
}

export function ResearchResultsPanel({ report }: ResearchResultsPanelProps) {
  const hasKG = (report.knowledge_graph_results?.length ?? 0) > 0;
  const hasKB = (report.knowledge_base_results?.length ?? 0) > 0;
  const hasMCP = (report.mcp_tool_results?.length ?? 0) > 0;
  const hasFed = (report.federation_results?.length ?? 0) > 0;
  const hasWeb = (report.web_results?.length ?? 0) > 0;
  const hasOverlaps = (report.overlap_warnings?.length ?? 0) > 0;

  return (
    <div className="space-y-4 max-h-[50vh] overflow-y-auto pr-1" data-testid="research-results">
      {/* Overlap Warnings */}
      {hasOverlaps && (
        <Card variant="outlined" padding="sm">
          <div className="flex items-center gap-2 mb-2 text-theme-warning">
            <AlertTriangle className="w-4 h-4" />
            <span className="text-sm font-medium">Similar skills detected</span>
          </div>
          <div className="space-y-1">
            {report.overlap_warnings?.map((s) => (
              <div key={s.id} className="flex justify-between items-center text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                <span className="text-theme-primary">{s.name}</span>
                <span className="text-theme-tertiary">{Math.round(s.similarity * 100)}% similar</span>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Suggested Skill */}
      {report.suggested_name && (
        <Card variant="outlined" padding="sm">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Suggested Skill</h4>
          <div className="space-y-1 text-sm">
            <div><span className="text-theme-tertiary">Name:</span> <span className="text-theme-primary">{report.suggested_name}</span></div>
            {report.suggested_category && (
              <div><span className="text-theme-tertiary">Category:</span> <span className="text-theme-primary">{report.suggested_category}</span></div>
            )}
            {report.suggested_description && (
              <div><span className="text-theme-tertiary">Description:</span> <span className="text-theme-secondary">{report.suggested_description}</span></div>
            )}
            {report.suggested_tags && report.suggested_tags.length > 0 && (
              <div className="flex gap-1 flex-wrap mt-1">
                {report.suggested_tags.map((tag) => (
                  <span key={tag} className="px-2 py-0.5 text-xs bg-theme-surface-secondary text-theme-secondary rounded">
                    {tag}
                  </span>
                ))}
              </div>
            )}
          </div>
        </Card>
      )}

      {/* Knowledge Graph Results */}
      {hasKG && (
        <Card variant="outlined" padding="sm">
          <div className="flex items-center gap-2 mb-2">
            <Link className="w-4 h-4 text-theme-secondary" />
            <span className="text-sm font-medium text-theme-primary">Knowledge Graph ({report.knowledge_graph_results?.length})</span>
          </div>
          <div className="space-y-1">
            {report.knowledge_graph_results?.slice(0, 5).map((r) => (
              <div key={r.node_id} className="flex justify-between text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                <span className="text-theme-primary">{r.name}</span>
                <span className="text-theme-tertiary">{Math.round(r.similarity * 100)}%</span>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Knowledge Base Results */}
      {hasKB && (
        <Card variant="outlined" padding="sm">
          <div className="flex items-center gap-2 mb-2">
            <Database className="w-4 h-4 text-theme-secondary" />
            <span className="text-sm font-medium text-theme-primary">Knowledge Bases ({report.knowledge_base_results?.length})</span>
          </div>
          <div className="space-y-1">
            {report.knowledge_base_results?.slice(0, 5).map((r) => (
              <div key={r.id} className="text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                <div className="text-theme-primary line-clamp-2">{r.content}</div>
                <div className="text-xs text-theme-tertiary mt-0.5">{r.source} - {Math.round(r.similarity * 100)}%</div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* MCP Tool Results */}
      {hasMCP && (
        <Card variant="outlined" padding="sm">
          <div className="flex items-center gap-2 mb-2">
            <Server className="w-4 h-4 text-theme-secondary" />
            <span className="text-sm font-medium text-theme-primary">MCP Tools ({report.mcp_tool_results?.length})</span>
          </div>
          <div className="space-y-1">
            {report.mcp_tool_results?.slice(0, 5).map((r) => (
              <div key={`${r.server_name}-${r.tool_name}`} className="text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                <span className="text-theme-primary">{r.server_name}/{r.tool_name}</span>
                <p className="text-xs text-theme-tertiary mt-0.5">{r.description}</p>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Federation Results */}
      {hasFed && (
        <Card variant="outlined" padding="sm">
          <div className="flex items-center gap-2 mb-2">
            <Globe className="w-4 h-4 text-theme-secondary" />
            <span className="text-sm font-medium text-theme-primary">Federation ({report.federation_results?.length})</span>
          </div>
          <div className="space-y-1">
            {report.federation_results?.slice(0, 5).map((r) => (
              <div key={r.endpoint} className="text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                <span className="text-theme-primary">{r.agent_name}</span>
                <div className="flex gap-1 flex-wrap mt-0.5">
                  {r.capabilities.slice(0, 3).map((c) => (
                    <span key={c} className="px-1.5 py-0.5 text-xs bg-theme-surface text-theme-tertiary rounded">{c}</span>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Web Results */}
      {hasWeb && (
        <Card variant="outlined" padding="sm">
          <div className="flex items-center gap-2 mb-2">
            <Globe className="w-4 h-4 text-theme-secondary" />
            <span className="text-sm font-medium text-theme-primary">Web ({report.web_results?.length})</span>
          </div>
          <div className="space-y-1">
            {report.web_results?.slice(0, 5).map((r, i) => (
              <div key={i} className="text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                <span className="text-theme-primary font-medium">{r.title}</span>
                <p className="text-xs text-theme-tertiary mt-0.5">{r.summary}</p>
              </div>
            ))}
          </div>
        </Card>
      )}

      {!hasKG && !hasKB && !hasMCP && !hasFed && !hasWeb && (
        <div className="text-center py-6 text-theme-tertiary text-sm">
          No results found. Try a different topic or enable more sources.
        </div>
      )}
    </div>
  );
}
