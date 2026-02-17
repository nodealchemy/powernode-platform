import React from 'react';
import { FileText, Play, TestTube, Eye, GitPullRequest, Rocket, Search, AlertCircle } from 'lucide-react';
import type { Mission, MissionWebSocketEvent, FeatureSuggestion } from '../../types/mission';
import { phaseLabel, isApprovalGate } from '../../types/mission';

interface PhaseCardProps {
  mission: Mission;
  events: MissionWebSocketEvent[];
}

const PhaseIcon: React.FC<{ phase: string }> = ({ phase }) => {
  const iconClass = 'w-5 h-5';
  if (phase.includes('analyz')) return <Search className={iconClass} />;
  if (phase.includes('plan')) return <FileText className={iconClass} />;
  if (phase.includes('execut')) return <Play className={iconClass} />;
  if (phase.includes('test')) return <TestTube className={iconClass} />;
  if (phase.includes('review')) return <Eye className={iconClass} />;
  if (phase.includes('deploy') || phase.includes('preview')) return <Rocket className={iconClass} />;
  if (phase.includes('merg')) return <GitPullRequest className={iconClass} />;
  return <Play className={iconClass} />;
};

const FeatureSuggestionCard: React.FC<{ feature: FeatureSuggestion; index: number }> = ({ feature, index }) => (
  <div className="p-3 bg-theme-surface rounded-lg border border-theme-border">
    <div className="flex items-start justify-between mb-1">
      <h4 className="text-sm font-medium text-theme-primary">{index + 1}. {feature.title}</h4>
      <span className="text-xs px-2 py-0.5 rounded bg-theme-accent/10 text-theme-accent flex-shrink-0 ml-2">
        {feature.complexity}
      </span>
    </div>
    <p className="text-xs text-theme-secondary mb-2">{feature.description}</p>
    {feature.files_affected.length > 0 && (
      <div className="flex flex-wrap gap-1">
        {feature.files_affected.slice(0, 5).map((f) => (
          <span key={f} className="text-[10px] px-1.5 py-0.5 bg-theme-surface-hover rounded text-theme-tertiary">
            {f}
          </span>
        ))}
        {feature.files_affected.length > 5 && (
          <span className="text-[10px] text-theme-tertiary">+{feature.files_affected.length - 5} more</span>
        )}
      </div>
    )}
  </div>
);

const AnalysisContent: React.FC<{ mission: Mission }> = ({ mission }) => {
  const analysis = mission.analysis_result;
  const suggestions = mission.feature_suggestions || [];

  if (Object.keys(analysis).length === 0) {
    return <p className="text-sm text-theme-secondary">Analyzing repository...</p>;
  }

  return (
    <div className="space-y-4">
      {analysis.tech_stack != null ? (
        <div>
          <h4 className="text-xs font-medium text-theme-secondary mb-1">Tech Stack</h4>
          <p className="text-sm text-theme-primary">{JSON.stringify(analysis.tech_stack)}</p>
        </div>
      ) : null}
      {suggestions.length > 0 && (
        <div>
          <h4 className="text-xs font-medium text-theme-secondary mb-2">Feature Suggestions</h4>
          <div className="space-y-2">
            {suggestions.map((s, i) => (
              <FeatureSuggestionCard key={i} feature={s} index={i} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

const PlanContent: React.FC<{ mission: Mission }> = ({ mission }) => {
  const prd = mission.prd_json;
  if (Object.keys(prd).length === 0) {
    return <p className="text-sm text-theme-secondary">Generating PRD...</p>;
  }

  return (
    <div className="space-y-3">
      {mission.branch_name && (
        <div className="flex items-center gap-2 text-sm">
          <span className="text-theme-secondary">Branch:</span>
          <code className="px-2 py-0.5 bg-theme-surface rounded text-theme-primary text-xs">{mission.branch_name}</code>
        </div>
      )}
      {mission.ralph_loop_id && (
        <div className="flex items-center gap-2 text-sm">
          <span className="text-theme-secondary">Ralph Loop:</span>
          <span className="text-theme-accent text-xs">{mission.ralph_loop_id}</span>
        </div>
      )}
      <div>
        <h4 className="text-xs font-medium text-theme-secondary mb-1">PRD</h4>
        <pre className="text-xs text-theme-primary bg-theme-surface p-3 rounded overflow-y-auto max-h-64 whitespace-pre-wrap break-words">
          {JSON.stringify(prd, null, 2)}
        </pre>
      </div>
    </div>
  );
};

const TestContent: React.FC<{ mission: Mission }> = ({ mission }) => {
  const result = mission.test_result;
  if (Object.keys(result).length === 0) {
    return <p className="text-sm text-theme-secondary">Running tests...</p>;
  }

  return (
    <div className="space-y-2">
      <pre className="text-xs text-theme-primary bg-theme-surface p-3 rounded overflow-y-auto max-h-64 whitespace-pre-wrap break-words">
        {JSON.stringify(result, null, 2)}
      </pre>
    </div>
  );
};

const ReviewContent: React.FC<{ mission: Mission }> = ({ mission }) => {
  const result = mission.review_result;
  if (Object.keys(result).length === 0) {
    return <p className="text-sm text-theme-secondary">Running code review...</p>;
  }

  return (
    <div className="space-y-2">
      <pre className="text-xs text-theme-primary bg-theme-surface p-3 rounded overflow-y-auto max-h-64 whitespace-pre-wrap break-words">
        {JSON.stringify(result, null, 2)}
      </pre>
    </div>
  );
};

const MergeContent: React.FC<{ mission: Mission }> = ({ mission }) => (
  <div className="space-y-3">
    {mission.pr_url ? (
      <div className="flex items-center gap-2">
        <GitPullRequest className="w-4 h-4 text-theme-success" />
        <a
          href={mission.pr_url}
          target="_blank"
          rel="noopener noreferrer"
          className="text-sm text-theme-accent hover:underline"
        >
          PR #{mission.pr_number} - View on Gitea
        </a>
      </div>
    ) : (
      <p className="text-sm text-theme-secondary">Creating pull request...</p>
    )}
  </div>
);

const EventLog: React.FC<{ events: MissionWebSocketEvent[] }> = ({ events }) => {
  if (events.length === 0) return null;

  return (
    <div className="mt-4 pt-4 border-t border-theme-border">
      <h4 className="text-xs font-medium text-theme-secondary mb-2">Recent Events</h4>
      <div className="space-y-1 max-h-32 overflow-y-auto">
        {events.slice(-10).reverse().map((evt, i) => (
          <div key={i} className="text-xs text-theme-tertiary flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-theme-accent flex-shrink-0" />
            <span>{evt.event}</span>
            <span className="ml-auto">{new Date(evt.timestamp).toLocaleTimeString()}</span>
          </div>
        ))}
      </div>
    </div>
  );
};

export const PhaseCard: React.FC<PhaseCardProps> = ({ mission, events }) => {
  const phase = mission.current_phase;

  if (!phase) {
    if (mission.status === 'completed') {
      return (
        <div className="card-theme-elevated p-6 text-center">
          <Rocket className="w-8 h-8 text-theme-success mx-auto mb-2" />
          <h3 className="text-lg font-medium text-theme-primary">Mission Completed</h3>
          <p className="text-sm text-theme-secondary mt-1">All phases finished successfully.</p>
        </div>
      );
    }
    return (
      <div className="card-theme-elevated p-6 text-center">
        <p className="text-sm text-theme-secondary">Mission has not started yet.</p>
      </div>
    );
  }

  return (
    <div className="card-theme-elevated p-5">
      <div className="flex items-center gap-3 mb-4">
        <div className="p-2 rounded-lg bg-theme-accent/10 text-theme-accent">
          <PhaseIcon phase={phase} />
        </div>
        <div>
          <h3 className="text-sm font-semibold text-theme-primary">{phaseLabel(phase)}</h3>
          {isApprovalGate(phase) && (
            <span className="text-xs text-theme-warning">Awaiting approval</span>
          )}
        </div>
        {mission.status === 'failed' && mission.error_message && (
          <div className="ml-auto flex items-center gap-1 text-theme-error">
            <AlertCircle className="w-4 h-4" />
            <span className="text-xs">{mission.error_message}</span>
          </div>
        )}
      </div>

      <div>
        {phase.includes('analyz') && <AnalysisContent mission={mission} />}
        {(phase.includes('plan') || phase === 'awaiting_prd_approval') && <PlanContent mission={mission} />}
        {phase === 'executing' && (
          <div className="space-y-2">
            <p className="text-sm text-theme-secondary">
              {mission.ralph_loop_id
                ? 'Ralph Loop is executing tasks...'
                : 'Starting execution...'}
            </p>
            {mission.ralph_loop_id && (
              <a
                href={`/app/ai/execution?ralph_loop=${mission.ralph_loop_id}`}
                className="text-xs text-theme-accent hover:underline"
              >
                View in Execution Dashboard
              </a>
            )}
          </div>
        )}
        {phase === 'testing' && <TestContent mission={mission} />}
        {(phase === 'reviewing' || phase === 'awaiting_code_approval') && <ReviewContent mission={mission} />}
        {(phase === 'deploying' || phase === 'previewing') && (
          <div className="space-y-2">
            {mission.deployed_url ? (
              <p className="text-sm text-theme-success">App deployed and ready for preview.</p>
            ) : (
              <p className="text-sm text-theme-secondary">Deploying application...</p>
            )}
          </div>
        )}
        {phase === 'merging' && <MergeContent mission={mission} />}
        {['researching', 'reporting', 'configuring', 'verifying'].includes(phase) && (
          <p className="text-sm text-theme-secondary">Processing...</p>
        )}
      </div>

      <EventLog events={events} />
    </div>
  );
};
