import { BookOpen, Star, Eye, Clock, Tag } from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, StatusBadge, formatDuration } from './DetailSection';
import { OutputViewer } from './OutputViewer';

export function TrajectoryDetail({ resource }: ResourceDetailProps) {
  const chapters = resource.chapters || [];
  const tags = resource.tags || [];

  return (
    <div className="space-y-4">
      {/* Summary */}
      {resource.summary && (
        <div className="p-3 rounded-lg border border-theme bg-theme-surface">
          <div className="text-xs text-theme-tertiary mb-1">Summary</div>
          <p className="text-sm text-theme-primary">{resource.summary}</p>
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        <StatCard label="Type" value={resource.trajectory_type} icon={<BookOpen className="w-3.5 h-3.5" />} />
        <StatCard
          label="Quality"
          value={resource.quality_score != null ? Number(resource.quality_score).toFixed(2) : undefined}
          icon={<Star className="w-3.5 h-3.5" />}
          variant={Number(resource.quality_score) >= 0.7 ? 'success' : Number(resource.quality_score) >= 0.4 ? 'warning' : 'danger'}
        />
        <StatCard label="Views" value={resource.access_count} icon={<Eye className="w-3.5 h-3.5" />} />
      </div>

      {/* Agent */}
      {resource.agent_name && (
        <div className="text-sm text-theme-secondary">
          Agent: <span className="font-medium text-theme-primary">{resource.agent_name}</span>
        </div>
      )}

      {/* Tags */}
      {tags.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          <Tag className="w-3.5 h-3.5 text-theme-tertiary mt-0.5" />
          {tags.map((tag) => (
            <span key={tag} className="px-2 py-0.5 text-xs rounded-full bg-theme-surface border border-theme text-theme-secondary">
              {tag}
            </span>
          ))}
        </div>
      )}

      {/* Outcome summary */}
      {resource.outcome_summary && Object.keys(resource.outcome_summary).length > 0 && (
        <DetailSection title="Outcome Summary" defaultOpen={false}>
          <OutputViewer data={resource.outcome_summary} />
        </DetailSection>
      )}

      {/* Chapters */}
      {chapters.length > 0 && (
        <DetailSection title={`Chapters (${chapters.length})`} defaultOpen>
          <div className="space-y-3">
            {chapters.map((chapter) => (
              <div key={chapter.chapter_number} className="border border-theme rounded-lg overflow-hidden">
                <div className="flex items-center gap-2 px-3 py-2 bg-theme-surface">
                  <span className="text-xs font-mono text-theme-tertiary">#{chapter.chapter_number}</span>
                  <span className="text-sm font-medium text-theme-primary flex-1">{chapter.title}</span>
                  <StatusBadge status={chapter.chapter_type} />
                  {chapter.duration_ms !== undefined && (
                    <span className="flex items-center gap-0.5 text-xs text-theme-tertiary">
                      <Clock className="w-3 h-3" />
                      {formatDuration(chapter.duration_ms)}
                    </span>
                  )}
                </div>
                <div className="p-3 space-y-2">
                  <p className="text-sm text-theme-primary whitespace-pre-wrap">{chapter.content}</p>

                  {chapter.reasoning && (
                    <div>
                      <div className="text-xs text-theme-tertiary mb-0.5">Reasoning</div>
                      <p className="text-sm text-theme-secondary whitespace-pre-wrap">{chapter.reasoning}</p>
                    </div>
                  )}

                  {chapter.key_decisions && chapter.key_decisions.length > 0 && (
                    <div>
                      <div className="text-xs text-theme-tertiary mb-0.5">Key Decisions ({chapter.key_decisions.length})</div>
                      <OutputViewer data={{ decisions: chapter.key_decisions }} />
                    </div>
                  )}

                  {chapter.artifacts && chapter.artifacts.length > 0 && (
                    <div>
                      <div className="text-xs text-theme-tertiary mb-0.5">Artifacts ({chapter.artifacts.length})</div>
                      <OutputViewer data={{ artifacts: chapter.artifacts }} />
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </DetailSection>
      )}
    </div>
  );
}
