/**
 * ErrorBoundary component that catches React rendering errors
 * and displays a graceful fallback UI instead of a white screen.
 *
 * Usage:
 * ```tsx
 * <ErrorBoundary>
 *   <YourComponent />
 * </ErrorBoundary>
 * ```
 */

import React, { Component, ReactNode, ErrorInfo } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode; // Optional custom fallback UI
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    // Update state so the next render shows the fallback UI
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    // Log error details with component stack trace
    console.error('ErrorBoundary caught an error:', error);
    console.error('Component stack:', errorInfo.componentStack);

    // Update state with error info
    this.setState({
      error,
      errorInfo,
    });

    // TODO: Send error to error tracking service (e.g., Sentry)
    // Example: logErrorToService(error, errorInfo);
  }

  handleReset = (): void => {
    // Reset error boundary state
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
    });
  };

  handleReload = (): void => {
    // Reload the entire app
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      // Custom fallback UI if provided
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // Default fallback UI
      const { error, errorInfo } = this.state;

      return (
        <div className="flex min-h-screen items-center justify-center bg-background p-6">
          <div className="max-w-2xl w-full rounded-lg border border-destructive/20 bg-card p-8 shadow-lg">
            <div className="flex items-center gap-3 mb-6">
              <AlertTriangle className="h-8 w-8 text-destructive" />
              <h1 className="text-2xl font-bold text-foreground">
                Something went wrong
              </h1>
            </div>

            <p className="text-muted-foreground mb-6">
              The application encountered an unexpected error. You can try reloading the page
              or resetting the error state.
            </p>

            <div className="mb-6 rounded-md bg-muted p-4 font-mono text-sm">
              <div className="font-semibold text-destructive mb-2">
                {error?.name || 'Error'}
              </div>
              <div className="text-foreground mb-4">
                {error?.message || 'Unknown error'}
              </div>
              {errorInfo && (
                <details className="mt-4">
                  <summary className="cursor-pointer text-muted-foreground hover:text-foreground">
                    Component stack trace
                  </summary>
                  <pre className="mt-2 max-h-64 overflow-auto text-xs text-muted-foreground whitespace-pre-wrap">
                    {errorInfo.componentStack}
                  </pre>
                </details>
              )}
            </div>

            <div className="flex gap-3">
              <button
                onClick={this.handleReset}
                className="flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 transition-colors"
              >
                <RefreshCw className="h-4 w-4" />
                Try Again
              </button>
              <button
                onClick={this.handleReload}
                className="flex items-center gap-2 rounded-md border border-input bg-background px-4 py-2 text-sm font-medium hover:bg-accent hover:text-accent-foreground transition-colors"
              >
                Reload App
              </button>
            </div>

            <div className="mt-6 text-xs text-muted-foreground">
              <p>
                If this problem persists, please check the developer console (Ctrl+Shift+I)
                for more details or contact support.
              </p>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

/**
 * Hook-based error boundary wrapper for functional components
 *
 * Example:
 * ```tsx
 * const MyComponent = () => {
 *   return (
 *     <ErrorBoundary>
 *       <YourFunctionalComponent />
 *     </ErrorBoundary>
 *   );
 * };
 * ```
 */
export const withErrorBoundary = <P extends object>(
  Component: React.ComponentType<P>,
  fallback?: ReactNode
): React.ComponentType<P> => {
  return (props: P) => (
    <ErrorBoundary fallback={fallback}>
      <Component {...props} />
    </ErrorBoundary>
  );
};
