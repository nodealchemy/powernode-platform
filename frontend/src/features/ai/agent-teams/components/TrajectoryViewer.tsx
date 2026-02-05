// Trajectory Viewer - Full trajectory timeline with chapters
import React, { useEffect, useState } from 'react';
import {
  Eye, BookOpen, Lightbulb, Code, TestTube, MessageSquare, GraduationCap,
  ChevronDown, ChevronUp, Clock, Star, Tag, FileText, ArrowLeft
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

      {/* Timeline */}
      <div className="relative" data-testid="trajectory-timeline">
        {/* Vertical line */}
        <div className="absolute left-6 top-0 bottom-0 w-0.5 bg-theme-accent" />

        {/* Chapters */}
        <div className="space-y-4">
          {trajectory.chapters?.map((chapter: TrajectoryChapter, idx: number) => (
            <ChapterCard
              key={chapter.id || idx}
              chapter={chapter}
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

// Chapter Card sub-component
const ChapterCard: React.FC<{
  chapter: TrajectoryChapter;
  isExpanded: boolean;
  onToggle: () => void;
}> = ({ chapter, isExpanded, onToggle }) => {
  const colorClass = CHAPTER_COLORS[chapter.chapter_type] || 'bg-theme-accent text-theme-primary border-theme';
  const icon = CHAPTER_ICONS[chapter.chapter_type] || <BookOpen size={16} />;

  return (
    <div className="relative pl-14" data-testid={`chapter-${chapter.chapter_type}`}>
      {/* Timeline node */}
      <div className={`absolute left-4 w-5 h-5 rounded-full border-2 flex items-center justify-center bg-theme-surface ${
        isExpanded ? 'border-theme-info' : 'border-theme-accent'
      }`}>
        <div className={`w-2 h-2 rounded-full ${isExpanded ? 'bg-theme-info' : 'bg-theme-accent'}`} />
      </div>

      {/* Card */}
      <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
        {/* Chapter Header */}
        <button
          type="button"
          onClick={onToggle}
          className="w-full flex items-center justify-between p-4 text-left hover:bg-theme-accent/50 transition-colors"
        >
          <div className="flex items-center gap-3">
            <span className={`p-1.5 rounded-md ${colorClass}`}>
              {icon}
            </span>
            <div>
              <h4 className="text-sm font-medium text-theme-primary">{chapter.title}</h4>
              <span className="text-xs text-theme-secondary capitalize">
                {chapter.chapter_type.replace(/_/g, ' ')}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-3">
            {chapter.duration_ms && (
              <span className="flex items-center gap-1 text-xs text-theme-secondary">
                <Clock size={12} />
                {formatDuration(chapter.duration_ms)}
              </span>
            )}
            {isExpanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
          </div>
        </button>

        {/* Expanded Content */}
        {isExpanded && (
          <div className="px-4 pb-4 space-y-3 border-t border-theme">
            {/* Content */}
            <div className="pt-3">
              <p className="text-sm text-theme-secondary whitespace-pre-wrap">{chapter.content}</p>
            </div>

            {/* Reasoning */}
            {chapter.reasoning && (
              <div className="p-3 bg-theme-accent/50 rounded-md">
                <h5 className="text-xs font-medium text-theme-secondary mb-1">Reasoning</h5>
                <p className="text-xs text-theme-secondary">{chapter.reasoning}</p>
              </div>
            )}

            {/* Key Decisions */}
            {chapter.key_decisions && chapter.key_decisions.length > 0 && (
              <div>
                <h5 className="text-xs font-medium text-theme-secondary mb-2">Key Decisions</h5>
                <div className="space-y-2">
                  {chapter.key_decisions.map((decision, idx) => (
                    <div key={idx} className="p-3 border border-theme-info/20 bg-theme-info/5 rounded-md">
                      <p className="text-xs font-medium text-theme-primary">
                        Decision: {decision.decision}
                      </p>
                      {decision.rationale && (
                        <p className="text-xs text-theme-secondary mt-1">
                          Rationale: {decision.rationale}
                        </p>
                      )}
                      {decision.alternatives && decision.alternatives.length > 0 && (
                        <p className="text-xs text-theme-secondary mt-1">
                          Alternatives: {decision.alternatives.join(', ')}
                        </p>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Artifacts */}
            {chapter.artifacts && chapter.artifacts.length > 0 && (
              <div>
                <h5 className="text-xs font-medium text-theme-secondary mb-2">Artifacts</h5>
                <div className="space-y-1">
                  {chapter.artifacts.map((artifact, idx) => (
                    <div key={idx} className="flex items-center gap-2 text-xs text-theme-secondary">
                      <FileText size={12} />
                      <span className="font-mono">{artifact.path}</span>
                      <span className={`px-1.5 py-0.5 rounded text-xs ${
                        artifact.action === 'new' ? 'bg-theme-success/10 text-theme-success' :
                        artifact.action === 'modified' ? 'bg-theme-info/10 text-theme-info' :
                        'bg-theme-danger/10 text-theme-danger'
                      }`}>
                        {artifact.action}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
