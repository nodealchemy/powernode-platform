// Loading state types and priorities
export type LoadingPriority = 'low' | 'medium' | 'high' | 'critical';

export interface LoadingState {
  isLoading: boolean;
  priority?: LoadingPriority;
  message?: string;
  progress?: number;
}

export type LoadingStateKey = string;
// Loading state action types