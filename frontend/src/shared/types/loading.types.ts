// Loading state types and priorities
export type LoadingPriority = 'low' | 'medium' | 'high' | 'critical';

export interface LoadingState {
  isLoading: boolean;
  priority?: LoadingPriority;
  message?: string;
  progress?: number;
}

export interface AsyncLoadingState<T = any> extends LoadingState {
  data?: T;
  error?: string;
  lastUpdated?: Date;
}

export type LoadingStateKey = string;

export interface GlobalLoadingState {
  [key: LoadingStateKey]: LoadingState;
}

// Loading state action types
export type LoadingAction = 
  | { type: 'START_LOADING'; key: string; priority?: LoadingPriority; message?: string }
  | { type: 'STOP_LOADING'; key: string }
  | { type: 'SET_PROGRESS'; key: string; progress: number }
  | { type: 'SET_ERROR'; key: string; error: string }
  | { type: 'CLEAR_ALL' };