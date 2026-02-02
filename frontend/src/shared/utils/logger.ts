/* eslint-disable no-console */
/**
 * Logger Utility
 *
 * Environment-aware logging utility that:
 * - Logs to console only in development mode
 * - Provides structured logging with timestamps
 * - Supports different log levels (debug, info, warn, error)
 * - Can be extended for production error reporting
 */

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LogContext {
  [key: string]: unknown;
}

interface LoggerConfig {
  enabled: boolean;
  minLevel: LogLevel;
  prefix?: string;
}

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3
};

const isDevelopment = process.env.NODE_ENV === 'development';
const isTest = process.env.NODE_ENV === 'test';

const defaultConfig: LoggerConfig = {
  enabled: isDevelopment && !isTest,
  minLevel: isDevelopment ? 'debug' : 'warn',
  prefix: '[Powernode]'
};

class Logger {
  private config: LoggerConfig;

  constructor(config: Partial<LoggerConfig> = {}) {
    this.config = { ...defaultConfig, ...config };
  }

  private shouldLog(level: LogLevel): boolean {
    if (!this.config.enabled) return false;
    return LOG_LEVELS[level] >= LOG_LEVELS[this.config.minLevel];
  }

  private formatMessage(level: LogLevel, message: string, context?: LogContext): string {
    const timestamp = new Date().toISOString();
    const prefix = this.config.prefix || '';
    const contextStr = context ? ` ${JSON.stringify(context)}` : '';
    return `${prefix} [${timestamp}] [${level.toUpperCase()}] ${message}${contextStr}`;
  }

  debug(message: string, context?: LogContext): void {
    if (this.shouldLog('debug')) {
      console.debug(this.formatMessage('debug', message, context));
    }
  }

  info(message: string, context?: LogContext): void {
    if (this.shouldLog('info')) {
      console.info(this.formatMessage('info', message, context));
    }
  }

  warn(message: string, context?: LogContext): void {
    if (this.shouldLog('warn')) {
      console.warn(this.formatMessage('warn', message, context));
    }
  }

  error(message: string, error?: Error | unknown, context?: LogContext): void {
    if (this.shouldLog('error')) {
      const errorContext = error instanceof Error
        ? { ...context, errorName: error.name, errorMessage: error.message, stack: error.stack }
        : { ...context, error };
      console.error(this.formatMessage('error', message, errorContext));
    }

    // In production, could send to error reporting service
    // if (process.env.NODE_ENV === 'production') {
    //   errorReportingService.capture(error);
    // }
  }

  /**
   * Log API call start
   */
  apiStart(method: string, url: string, context?: LogContext): void {
    this.debug(`API ${method} ${url}`, context);
  }

  /**
   * Log API call completion
   */
  apiComplete(method: string, url: string, duration: number, context?: LogContext): void {
    this.debug(`API ${method} ${url} completed`, { ...context, duration: `${duration}ms` });
  }

  /**
   * Log API error
   */
  apiError(method: string, url: string, error: unknown, context?: LogContext): void {
    this.error(`API ${method} ${url} failed`, error, context);
  }

  /**
   * Create a child logger with a specific prefix
   */
  child(prefix: string): Logger {
    return new Logger({
      ...this.config,
      prefix: `${this.config.prefix} [${prefix}]`
    });
  }
}

// Export singleton instance for general use
export const logger = new Logger();

// Export class for creating custom loggers
export { Logger };
export type { LogLevel, LogContext, LoggerConfig };
