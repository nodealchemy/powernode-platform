import React, { Component, ErrorInfo, ReactNode } from 'react';
import { AlertTriangle, RefreshCw, Home, Bug } from 'lucide-react';

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
  errorId: string;
  retryCount: number;
}

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo, errorId: string) => void;
  maxRetries?: number;
  showDetails?: boolean;
  level?: 'page' | 'section' | 'component';
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  private retryTimeoutId: NodeJS.Timeout | null = null;

  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
      errorId: '',
      retryCount: 0
    };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    const errorId = `err_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    return {
      hasError: true,
      error,
      errorId
    };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    const { onError } = this.props;
    const { errorId } = this.state;

    this.setState({ errorInfo });

    // Log error details with enhanced debugging for page refresh investigation
    console.group(`🚨 ERROR BOUNDARY TRIGGERED - POTENTIAL REFRESH CAUSE [${errorId}]`);
    console.error('⚠️ ERROR BOUNDARY: This error may be causing automatic page refreshes!');
    console.error('Error:', error);
    console.error('Error Message:', error.message);
    console.error('Error Info:', errorInfo);
    console.error('Component Stack:', errorInfo.componentStack);
    console.trace('Stack trace when error boundary triggered:');
    console.groupEnd();

    // Report to external error tracking service
    if (onError) {
      onError(error, errorInfo, errorId);
    }

    // In development, also report to browser console for easier debugging
    if (process.env.NODE_ENV === 'development') {
      console.warn('Error Boundary Details:', {
        message: error.message,
        stack: error.stack,
        componentStack: errorInfo.componentStack,
        errorId
      });
    }
  }

  handleRetry = () => {
    const { maxRetries = 3 } = this.props;
    const { retryCount } = this.state;

    if (retryCount < maxRetries) {
      this.setState(prevState => ({
        hasError: false,
        error: null,
        errorInfo: null,
        retryCount: prevState.retryCount + 1
      }));

      // Clear any existing timeout
      if (this.retryTimeoutId) {
        clearTimeout(this.retryTimeoutId);
      }

      // Auto-retry with exponential backoff for network errors
      if (this.isNetworkError(this.state.error)) {
        const delay = Math.min(1000 * Math.pow(2, retryCount), 10000);
        this.retryTimeoutId = setTimeout(() => {
          this.handleRetry();
        }, delay);
      }
    }
  };

  handleReset = () => {
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
      retryCount: 0
    });
  };

  handleReload = () => {
    window.location.reload();
  };

  handleNavigateHome = () => {
    window.location.href = '/';
  };

  isNetworkError = (error: Error | null): boolean => {
    if (!error) return false;
    const networkErrorMessages = [
      'network error',
      'fetch error',
      'connection failed',
      'timeout',
      'net::',
      'failed to fetch'
    ];
    return networkErrorMessages.some(msg => 
      error.message.toLowerCase().includes(msg)
    );
  };

  isChunkLoadError = (error: Error | null): boolean => {
    if (!error) return false;
    return error.message.includes('Loading chunk') || 
           error.message.includes('Loading CSS chunk');
  };

  getErrorSeverity = (): 'low' | 'medium' | 'high' | 'critical' => {
    const { error } = this.state;
    if (!error) return 'low';

    if (this.isChunkLoadError(error)) return 'medium';
    if (this.isNetworkError(error)) return 'medium';
    if (error.name === 'ChunkLoadError') return 'medium';
    if (error.message.includes('Permission denied')) return 'high';
    if (error.message.includes('Memory')) return 'critical';
    
    return 'high';
  };

  renderErrorDetails = () => {
    const { showDetails = process.env.NODE_ENV === 'development' } = this.props;
    const { error, errorInfo, errorId } = this.state;

    if (!showDetails || !error) return null;

    return (
      <details className="mt-4 p-4 bg-theme-background rounded-lg border border-theme">
        <summary className="cursor-pointer text-sm font-medium text-theme-secondary hover:text-theme-primary">
          Technical Details (Error ID: {errorId})
        </summary>
        <div className="mt-3 space-y-3">
          <div>
            <h4 className="text-sm font-medium text-theme-primary">Error Message:</h4>
            <p className="text-sm text-theme-error font-mono bg-theme-surface p-2 rounded mt-1">
              {error.message}
            </p>
          </div>
          <div>
            <h4 className="text-sm font-medium text-theme-primary">Stack Trace:</h4>
            <pre className="text-xs text-theme-secondary font-mono bg-theme-surface p-2 rounded mt-1 overflow-auto max-h-32">
              {error.stack}
            </pre>
          </div>
          {errorInfo && (
            <div>
              <h4 className="text-sm font-medium text-theme-primary">Component Stack:</h4>
              <pre className="text-xs text-theme-secondary font-mono bg-theme-surface p-2 rounded mt-1 overflow-auto max-h-32">
                {errorInfo.componentStack}
              </pre>
            </div>
          )}
        </div>
      </details>
    );
  };

  renderErrorActions = () => {
    const { maxRetries = 3, level = 'component' } = this.props;
    const { retryCount } = this.state;
    const canRetry = retryCount < maxRetries;
    const severity = this.getErrorSeverity();

    return (
      <div className="flex flex-col sm:flex-row gap-3 mt-6">
        {canRetry && (
          <button
            onClick={this.handleRetry}
            className="inline-flex items-center px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors duration-200"
          >
            <RefreshCw className="w-4 h-4 mr-2" />
            Try Again {retryCount > 0 && `(${retryCount}/${maxRetries})`}
          </button>
        )}
        
        <button
          onClick={this.handleReset}
          className="inline-flex items-center px-4 py-2 bg-theme-interactive-secondary text-white rounded-lg hover:bg-theme-interactive-secondary-hover transition-colors duration-200"
        >
          Reset Component
        </button>

        {level === 'page' && (
          <button
            onClick={this.handleNavigateHome}
            className="inline-flex items-center px-4 py-2 bg-theme-surface text-theme-primary rounded-lg hover:bg-theme-surface-hover transition-colors duration-200"
          >
            <Home className="w-4 h-4 mr-2" />
            Go Home
          </button>
        )}

        {severity === 'critical' && (
          <button
            onClick={this.handleReload}
            className="inline-flex items-center px-4 py-2 bg-theme-warning text-white rounded-lg hover:bg-theme-warning-hover transition-colors duration-200"
          >
            <RefreshCw className="w-4 h-4 mr-2" />
            Reload Page
          </button>
        )}
      </div>
    );
  };

  render() {
    const { hasError, error } = this.state;
    const { children, fallback, level = 'component' } = this.props;

    if (hasError) {
      if (fallback) {
        return fallback;
      }

      const severity = this.getErrorSeverity();
      const isChunkError = this.isChunkLoadError(error);
      const isNetworkError = this.isNetworkError(error);

      return (
        <div className="flex flex-col items-center justify-center p-8 text-center min-h-[400px] bg-theme-background rounded-lg border border-theme">
          <div className={`p-4 rounded-full mb-6 ${
            severity === 'critical' ? 'bg-theme-error bg-opacity-20' :
            severity === 'high' ? 'bg-theme-warning bg-opacity-20' :
            'bg-theme-info bg-opacity-20'
          }`}>
            {severity === 'critical' ? (
              <Bug className="w-12 h-12 text-theme-error" />
            ) : (
              <AlertTriangle className={`w-12 h-12 ${
                severity === 'high' ? 'text-theme-warning' : 'text-theme-info'
              }`} />
            )}
          </div>

          <h2 className="text-2xl font-bold text-theme-primary mb-3">
            {isChunkError ? 'Update Available' :
             isNetworkError ? 'Connection Problem' :
             severity === 'critical' ? 'Critical Error' :
             'Something went wrong'}
          </h2>

          <p className="text-theme-secondary mb-6 max-w-md">
            {isChunkError ? 
              'The application has been updated. Please refresh the page to load the latest version.' :
             isNetworkError ?
              'Unable to connect to the server. Please check your internet connection and try again.' :
             severity === 'critical' ?
              'A critical error has occurred. Please reload the page or contact support if the problem persists.' :
              level === 'section' ?
              'We encountered an unexpected error in this section. You can try to recover or reload the page.' :
              `We encountered an unexpected error in this ${level}. You can try to recover or reload the page.`}
          </p>

          {this.renderErrorActions()}
          {this.renderErrorDetails()}
        </div>
      );
    }

    return children;
  }

  componentWillUnmount() {
    if (this.retryTimeoutId) {
      clearTimeout(this.retryTimeoutId);
    }
  }
}

// Convenience wrapper for page-level error boundaries
export const PageErrorBoundary: React.FC<Omit<ErrorBoundaryProps, 'level'>> = (props) => (
  <ErrorBoundary {...props} level="page" />
);

// Convenience wrapper for section-level error boundaries
export const SectionErrorBoundary: React.FC<Omit<ErrorBoundaryProps, 'level'>> = (props) => (
  <ErrorBoundary {...props} level="section" />
);

export default ErrorBoundary;