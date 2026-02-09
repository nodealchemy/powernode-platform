import { Link } from 'react-router-dom';

interface ResourceSourceLinkProps {
  sourceType: string;
  sourceId: string;
}

const SOURCE_ROUTES: Record<string, string> = {
  'Ai::A2aTask': '/app/ai/a2a-tasks',
  'Ai::Worktree': '/app/ai/parallel-execution',
  'Ai::MergeOperation': '/app/ai/parallel-execution',
  'Ai::TeamExecution': '/app/ai/teams',
  'Ai::MemoryPool': '/app/ai/teams',
  'Ai::Trajectory': '/app/ai/learning/insights',
  'Ai::TaskReview': '/app/ai/teams',
  'Ai::RunnerDispatch': '/app/ai/parallel-execution',
};

export function ResourceSourceLink({ sourceType, sourceId: _sourceId }: ResourceSourceLinkProps) {
  const route = SOURCE_ROUTES[sourceType];

  if (!route) {
    return <span className="text-xs text-theme-text-tertiary">{sourceType.split('::').pop()}</span>;
  }

  return (
    <Link
      to={route}
      onClick={(e) => e.stopPropagation()}
      className="text-xs text-theme-primary hover:underline"
    >
      {sourceType.split('::').pop()}
    </Link>
  );
}
