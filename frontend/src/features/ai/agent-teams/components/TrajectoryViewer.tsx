// Trajectory Viewer - Collapsible tree view with chapters, decisions, and artifacts
import React, { useEffect, useState } from 'react';
import {
  Eye, BookOpen, Lightbulb, Code, TestTube, MessageSquare, GraduationCap,
  ChevronDown, ChevronRight, Clock, Star, Tag, FileText, ArrowLeft,
  ChevronsDownUp, ChevronsUpDown, GitBranch, CircleDot
} from 'lucide-react';
import teamsApi from '@/shared/services/ai/TeamsApiService';
import type { TrajectoryWithChapters, TrajectoryChapter } from '@/shared/services/ai/TeamsApiService';

interface TrajectoryViewerProps {
  trajectoryId: string;
  onBack?: () => void;
}

const CHAPTER_ICONS: Record<string, React.ReactNode> = {
  understanding: <Eye size={16} />,
  investigation: <BookOpen size={16} />,
  planning: <Lightbulb size={16} />,
  implementation: <Code size={16} />,
  testing: <TestTube size={16} />,
  reflection: <MessageSquare size={16} />,
  lessons_learned: <GraduationCap size={16} />,
};

const CHAPTER_COLORS: Record<string, string> = {
  understanding: 'bg-theme-info/10 text-theme-info border-theme-info/30',
  investigation: 'bg-theme-interactive-primary/10 text-theme-interactive-primary border-theme-interactive-primary/30',
  planning: 'bg-theme-warning/10 text-theme-warning border-theme-warning/30',
  implementation: 'bg-theme-success/10 text-theme-success border-theme-success/30',
  testing: 'bg-theme-danger/10 text-theme-danger border-theme-danger/30',
  reflection: 'bg-theme-secondary/10 text-theme-secondary border-theme-secondary/30',
  lessons_learned: 'bg-theme-interactive-primary/10 text-theme-interactive-primary border-theme-interactive-primary/30',
};

const formatDuration = (ms: number | undefined): string => {
  if (!ms) return '';
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  if (minutes > 0) return `${minutes}m ${remainingSeconds}s`;
  return `${remainingSeconds}s`;
};

export const TrajectoryViewer: React.FC<TrajectoryViewerProps> = ({
  trajectoryId,
  onBack
}) => {
  const [trajectory, setTrajectory] = useState<TrajectoryWithChapters | null>(null);
  const [loading, setLoading] = useState(true);
  const [expandedChapters, setExpandedChapters] = useState<Set<number>>(new Set());

  useEffect(() => {
    fetchTrajectory();
  }, [trajectoryId]);

  const fetchTrajectory = async () => {
    setLoading(true);
    try {
      const data = await teamsApi.getTrajectory(trajectoryId);
      setTrajectory(data);
      // Auto-expand first chapter
      if (data.chapters?.length) {
        setExpandedChapters(new Set([0]));
      }
    } catch {
      // Error handled by API service
    } finally {
      setLoading(false);
    }
  };

  const toggleChapter = (index: number) => {
    setExpandedChapters(prev => {
      const next = new Set(prev);
      if (next.has(index)) {
        next.delete(index);
      } else {
        next.add(index);
      }
      return next;
    });
  };

  const expandAll = () => {
    if (!trajectory?.chapters) return;
    setExpandedChapters(new Set(trajectory.chapters.map((_, i) => i)));
  };

  const collapseAll = () => {
    setExpandedChapters(new Set());
  };

  const allExpanded = trajectory?.chapters?.length
    ? expandedChapters.size === trajectory.chapters.length
    : false;

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12 text-theme-secondary">
        Loading trajectory...
      </div>
    );
  }

  if (!trajectory) {
    return (
      <div className="text-center py-12 text-theme-secondary">
        Trajectory not found
      </div>
    );
  }

  return (
    <div className="space-y-6" data-testid="trajectory-viewer">
      {/* Header */}
      <div className="bg-theme-surface border border-theme rounded-lg p-6">
        {onBack && (
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-1 text-sm text-theme-secondary hover:text-theme-primary mb-4"
          >
            <ArrowLeft size={16} /> Back to Trajectories
          </button>
        )}

        <div className="flex items-start justify-between">
          <div>
            <h2 className="text-lg font-semibold text-theme-primary mb-2">{trajectory.title}</h2>

            <div className="flex flex-wrap gap-4 text-sm text-theme-secondary">
              <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                CHAPTER_COLORS[trajectory.trajectory_type] || 'bg-theme-accent text-theme-primary'
              }`}>
                {trajectory.trajectory_type.replace(/_/g, ' ')}
              </span>

              {trajectory.quality_score !== null && trajectory.quality_score !== undefined && (
                <span className="flex items-center gap-1">
                  <Star size={14} className="text-theme-warning" />
                  {trajectory.quality_score.toFixed(2)}
                </span>
              )}

              <span className="flex items-center gap-1">
                <BookOpen size={14} />
                {trajectory.chapter_count} chapters
              </span>

              <span className="flex items-center gap-1">
                <Eye size={14} />
                {trajectory.access_count} views
              </span>
            </div>
          </div>

          {/* Expand/Collapse All */}
          {trajectory.chapters && trajectory.chapters.length > 1 && (
            <button
              type="button"
              onClick={allExpanded ? collapseAll : expandAll}
              className="flex items-center gap-1 px-2 py-1 text-xs text-theme-secondary hover:text-theme-primary hover:bg-theme-accent rounded transition-colors"
              title={allExpanded ? 'Collapse all' : 'Expand all'}
            >
              {allExpanded ? <ChevronsDownUp size={14} /> : <ChevronsUpDown size={14} />}
              {allExpanded ? 'Collapse All' : 'Expand All'}
            </button>
          )}
        </div>

        {/* Tags */}
        {trajectory.tags && trajectory.tags.length > 0 && (
          <div className="flex flex-wrap gap-2 mt-3">
            {trajectory.tags.map((tag: string, idx: number) => (
              <span key={idx} className="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-accent text-theme-secondary">
                <Tag size={10} />
                {tag}
              </span>
            ))}
          </div>
        )}

        {/* Summary */}
        {trajectory.summary && (
          <p className="mt-3 text-sm text-theme-secondary">{trajectory.summary}</p>
        )}
      </div>

      {/* Tree View */}
      <div data-testid="trajectory-timeline">
        <div className="space-y-1">
          {trajectory.chapters?.map((chapter: TrajectoryChapter, idx: number) => (
            <ChapterTreeNode
              key={chapter.id || idx}
              chapter={chapter}
              index={idx}
              isLast={idx === (trajectory.chapters?.length ?? 0) - 1}
              isExpanded={expandedChapters.has(idx)}
              onToggle={() => toggleChapter(idx)}
            />
          ))}
        </div>
      </div>

      {/* Outcome Summary */}
      {trajectory.outcome_summary && Object.keys(trajectory.outcome_summary).length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-lg p-4">
          <h3 className="text-sm font-medium text-theme-primary mb-3">Outcome Summary</h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {Object.entries(trajectory.outcome_summary).map(([key, value]) => (
              <div key={key} className="text-center">
                <div className="text-lg font-semibold text-theme-primary">{String(value)}</div>
                <div className="text-xs text-theme-secondary">{key.replace(/_/g, ' ')}</div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

// Chapter tree node with nested decisions and artifacts
const ChapterTreeNode: React.FC<{
  chapter: TrajectoryChapter;
  index: number;
  isLast: boolean;
  isExpanded: boolean;
  onToggle: () => void;
}> = ({ chapter, index, isExpanded, onToggle }) => {
  const colorClass = CHAPTER_COLORS[chapter.chapter_type] || 'bg-theme-accent text-theme-primary border-theme';
  const icon = CHAPTER_ICONS[chapter.chapter_type] || <BookOpen size={16} />;

  const hasDecisions = chapter.key_decisions && chapter.key_decisions.length > 0;
  const hasArtifacts = chapter.artifacts && chapter.artifacts.length > 0;
  const hasContent = chapter.content || chapter.reasoning;
  const hasChildren = hasDecisions || hasArtifacts || hasContent;

  return (
    <div className="relative" data-testid={`chapter-${chapter.chapter_type}`}>
      {/* Chapter header row */}
      <button
        type="button"
        onClick={onToggle}
        className="w-full flex items-center gap-2 p-2 rounded-md hover:bg-theme-accent/50 transition-colors text-left group"
      >
        {/* Expand/collapse indicator */}
        <span className="flex-shrink-0 w-4 h-4 flex items-center justify-center text-theme-secondary">
          {hasChildren ? (
            isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />
          ) : (
            <CircleDot size={10} className="text-theme-accent" />
          )}
        </span>

        {/* Chapter icon */}
        <span className={`flex-shrink-0 p-1 rounded-md ${colorClass}`}>
          {icon}
        </span>

        {/* Chapter info */}
        <div className="flex-1 min-w-0">
          <span className="text-sm font-medium text-theme-primary">
            Chapter {index + 1}: {chapter.title}
          </span>
        </div>

        {/* Metadata badges */}
        <div className="flex items-center gap-2 flex-shrink-0">
          {hasDecisions && (
            <span className="text-xs text-theme-secondary flex items-center gap-0.5" title="Decisions">
              <GitBranch size={11} />
              {chapter.key_decisions.length}
            </span>
          )}
          {hasArtifacts && (
            <span className="text-xs text-theme-secondary flex items-center gap-0.5" title="Artifacts">
              <FileText size={11} />
              {chapter.artifacts.length}
            </span>
          )}
          {chapter.duration_ms ? (
            <span className="text-xs text-theme-secondary flex items-center gap-0.5">
              <Clock size={11} />
              {formatDuration(chapter.duration_ms)}
            </span>
          ) : null}
          <span className={`px-1.5 py-0.5 rounded text-xs capitalize ${colorClass}`}>
            {chapter.chapter_type.replace(/_/g, ' ')}
          </span>
        </div>
      </button>

      {/* Expanded children — nested tree with connecting lines */}
      {isExpanded && hasChildren && (
        <div className="ml-4 pl-4 border-l-2 border-theme-accent">
          {/* Content */}
          {chapter.content && (
            <div className="relative py-2 pl-4">
              <div className="absolute left-0 top-4 w-4 h-0 border-t border-theme-accent" />
              <p className="text-sm text-theme-secondary whitespace-pre-wrap">{chapter.content}</p>
            </div>
          )}

          {/* Reasoning */}
          {chapter.reasoning && (
            <div className="relative py-2 pl-4">
              <div className="absolute left-0 top-4 w-4 h-0 border-t border-theme-accent" />
              <div className="p-3 bg-theme-accent/50 rounded-md">
                <h5 className="text-xs font-medium text-theme-secondary mb-1">Reasoning</h5>
                <p className="text-xs text-theme-secondary">{chapter.reasoning}</p>
              </div>
            </div>
          )}

          {/* Key Decisions as tree nodes */}
          {hasDecisions && (
            <div className="py-1">
              {chapter.key_decisions.map((decision, idx) => (
                <DecisionNode
                  key={idx}
                  decision={decision}
                  isLast={idx === chapter.key_decisions.length - 1 && !hasArtifacts}
                />
              ))}
            </div>
          )}

          {/* Artifacts as tree nodes */}
          {hasArtifacts && (
            <div className="py-1">
              <div className="relative pl-4 py-1">
                <div className="absolute left-0 top-3 w-4 h-0 border-t border-theme-accent" />
                <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Artifacts</h5>
              </div>
              {chapter.artifacts.map((artifact, idx) => (
                <div key={idx} className="relative pl-8 py-0.5">
                  <div className="absolute left-4 top-2.5 w-4 h-0 border-t border-dashed border-theme-accent" />
                  <div className="flex items-center gap-2 text-xs text-theme-secondary">
                    <FileText size={12} className="flex-shrink-0" />
                    <span className="font-mono truncate">{artifact.path}</span>
                    <span className={`flex-shrink-0 px-1.5 py-0.5 rounded text-xs ${
                      artifact.action === 'new' ? 'bg-theme-success/10 text-theme-success' :
                      artifact.action === 'modified' ? 'bg-theme-info/10 text-theme-info' :
                      'bg-theme-danger/10 text-theme-danger'
                    }`}>
                      {artifact.action}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

// Decision tree node with rationale and alternatives
const DecisionNode: React.FC<{
  decision: { decision: string; rationale: string; alternatives: string[] };
  isLast: boolean;
}> = ({ decision }) => {
  const [expanded, setExpanded] = useState(false);
  const hasDetails = decision.rationale || (decision.alternatives && decision.alternatives.length > 0);

  return (
    <div className="relative pl-4">
      <div className="absolute left-0 top-3 w-4 h-0 border-t border-theme-accent" />

      <button
        type="button"
        onClick={() => hasDetails && setExpanded(!expanded)}
        className={`w-full text-left flex items-start gap-2 py-1.5 px-2 rounded-md ${
          hasDetails ? 'hover:bg-theme-accent/30 cursor-pointer' : 'cursor-default'
        } transition-colors`}
      >
        <span className="flex-shrink-0 mt-0.5 w-3.5 h-3.5 flex items-center justify-center">
          {hasDetails ? (
            expanded ? <ChevronDown size={12} className="text-theme-secondary" /> : <ChevronRight size={12} className="text-theme-secondary" />
          ) : (
            <GitBranch size={12} className="text-theme-info" />
          )}
        </span>
        <span className="text-xs font-medium text-theme-primary">{decision.decision}</span>
      </button>

      {expanded && hasDetails && (
        <div className="ml-4 pl-4 border-l border-dashed border-theme-info/30 pb-1">
          {decision.rationale && (
            <div className="py-1">
              <p className="text-xs text-theme-secondary">
                <span className="font-medium">Rationale:</span> {decision.rationale}
              </p>
            </div>
          )}
          {decision.alternatives && decision.alternatives.length > 0 && (
            <div className="py-1">
              <p className="text-xs text-theme-secondary">
                <span className="font-medium">Alternatives:</span> {decision.alternatives.join(', ')}
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
