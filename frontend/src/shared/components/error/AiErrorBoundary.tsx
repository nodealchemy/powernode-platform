import { Component, ErrorInfo, ReactNode } from 'react';
import { AlertCircle, RefreshCw } from 'lucide-react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
  onRetry?: () => void;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

/**
 * Error Boundary for AI Orchestration Components
 *
 * Catches JavaScript errors in child component tree, logs errors,
 * and displays a fallback UI instead of crashing the whole page.
 *
 * @example
 * ```tsx
 * <AiErrorBoundary onRetry={() => window.location.reload()}>
 *   <AIMonitoringPage />
 * </AiErrorBoundary>
 * ```
 */
export class AiErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    // Log error for debugging
    if (process.env.NODE_ENV === 'development') {
      console.error('[AiErrorBoundary] Component Error:', error);
      console.error('[AiErrorBoundary] Error Info:', errorInfo);
    }

    // Call optional error callback
    this.props.onError?.(error, errorInfo);
  }

  private handleRetry = (): void => {
    this.setState({ hasError: false, error: null });
    this.props.onRetry?.();
  };

  public render(): ReactNode {
    if (this.state.hasError) {
      // Use custom fallback if provided
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // Default fallback UI
      return (
        <div className="flex flex-col items-center justify-center p-8 bg-theme-surface border border-theme rounded-lg">
          <AlertCircle className="w-12 h-12 text-theme-error mb-4" />
          <h2 className="text-lg font-semibold text-theme-primary mb-2">
            Something went wrong
          </h2>
          <p className="text-theme-secondary text-sm mb-4 text-center max-w-md">
            {this.state.error?.message || 'An unexpected error occurred in this component.'}
          </p>
          <button
            onClick={this.handleRetry}
            className="flex items-center gap-2 px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors"
          >
            <RefreshCw className="w-4 h-4" />
            Try Again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

/**
 * Minimal error boundary variant for smaller components
 */
export class MinimalErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    if (process.env.NODE_ENV === 'development') {
      console.error('[MinimalErrorBoundary] Error:', error, errorInfo);
    }
    this.props.onError?.(error, errorInfo);
  }

  private handleRetry = (): void => {
    this.setState({ hasError: false, error: null });
    this.props.onRetry?.();
  };

  public render(): ReactNode {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="flex items-center gap-2 p-3 text-theme-error text-sm">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          <span>Error loading component</span>
          <button
            onClick={this.handleRetry}
            className="ml-2 text-theme-interactive-primary hover:underline"
          >
            Retry
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

export default AiErrorBoundary;
