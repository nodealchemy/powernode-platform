import { Component, ErrorInfo, ReactNode } from 'react';
import { CreditCard, RefreshCw, AlertCircle } from 'lucide-react';

interface Props {
  children: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
  onRetry?: () => void;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

/**
 * Error boundary specifically for billing/payment components.
 * Provides a user-friendly error UI with retry functionality
 * and proper error logging for billing-critical operations.
 */
export class BillingErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
    errorInfo: null,
  };

  public static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    this.setState({ errorInfo });

    // Log error for debugging
    if (process.env.NODE_ENV === 'development') {
      console.error('[BillingErrorBoundary] Component Error:', error);
      console.error('[BillingErrorBoundary] Error Info:', errorInfo);
    }

    // Notify parent component
    this.props.onError?.(error, errorInfo);
  }

  private handleRetry = (): void => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    this.props.onRetry?.();
  };

  private getErrorMessage(): string {
    const { error } = this.state;

    if (!error) {
      return 'An error occurred while processing your billing request.';
    }

    // Check for common billing error patterns
    const message = error.message.toLowerCase();

    if (message.includes('network') || message.includes('connection')) {
      return 'Unable to connect to the payment service. Please check your internet connection.';
    }

    if (message.includes('payment') || message.includes('card') || message.includes('declined')) {
      return 'There was a problem processing your payment. Please try again or use a different payment method.';
    }

    if (message.includes('timeout')) {
      return 'The payment service is taking longer than expected. Please try again.';
    }

    if (message.includes('unauthorized') || message.includes('session')) {
      return 'Your session has expired. Please log in again to continue.';
    }

    return error.message || 'An error occurred while processing your billing request.';
  }

  public render(): ReactNode {
    if (this.state.hasError) {
      // Use custom fallback if provided
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="flex flex-col items-center justify-center p-8 bg-theme-surface border border-theme-error rounded-lg">
          <div className="flex items-center justify-center w-16 h-16 rounded-full bg-theme-error-background mb-4">
            <CreditCard className="w-8 h-8 text-theme-error" />
          </div>

          <h2 className="text-lg font-semibold text-theme-primary mb-2">
            Billing Error
          </h2>

          <p className="text-theme-secondary text-sm mb-4 text-center max-w-md">
            {this.getErrorMessage()}
          </p>

          <div className="flex items-center gap-2 text-theme-tertiary text-xs mb-4">
            <AlertCircle className="w-3 h-3" />
            <span>If this issue persists, please contact support.</span>
          </div>

          <button
            onClick={this.handleRetry}
            className="flex items-center gap-2 px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors"
          >
            <RefreshCw className="w-4 h-4" />
            Try Again
          </button>

          {process.env.NODE_ENV === 'development' && this.state.error && (
            <details className="mt-4 w-full max-w-md">
              <summary className="text-xs text-theme-tertiary cursor-pointer hover:text-theme-secondary">
                Technical Details
              </summary>
              <pre className="mt-2 p-2 bg-theme-surface-hover rounded text-xs text-theme-secondary overflow-auto">
                {this.state.error.stack || this.state.error.message}
              </pre>
            </details>
          )}
        </div>
      );
    }

    return this.props.children;
  }
}

export default BillingErrorBoundary;
