/**
 * Consistent error formatting utilities for the Medusa trading terminal.
 * All error display should use these formatters for uniform UX.
 */

/**
 * Format any error into a user-friendly string.
 * Handles Error objects, strings, and unknown types.
 */
export function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }
  if (typeof error === 'string') {
    return error
  }
  if (error && typeof error === 'object') {
    // Handle objects with message property
    const errorObj = error as Record<string, unknown>
    if (errorObj.message && typeof errorObj.message === 'string') {
      return errorObj.message
    }
    // Handle objects with error property
    if (errorObj.error && typeof errorObj.error === 'string') {
      return errorObj.error
    }
  }
  return 'An unexpected error occurred'
}

/**
 * Format kdb+ result errors consistently.
 * Handles the { success: boolean; error?: string } pattern from IPC handlers.
 */
export function formatKdbError(result: { success: boolean; error?: string; data?: unknown }): string {
  if (result.success) {
    return ''
  }
  if (result.error) {
    return result.error
  }
  return 'Unknown kdb+ error'
}

/**
 * Format validation errors (typically from form validation).
 * Converts validation error objects into readable messages.
 */
export function formatValidationError(errors: Record<string, string[]> | string[]): string {
  if (Array.isArray(errors)) {
    return errors.join(', ')
  }
  const messages: string[] = []
  for (const [field, fieldErrors] of Object.entries(errors)) {
    if (Array.isArray(fieldErrors) && fieldErrors.length > 0) {
      messages.push(`${field}: ${fieldErrors.join(', ')}`)
    }
  }
  return messages.join('; ')
}

/**
 * Format network/fetch errors with helpful context.
 */
export function formatNetworkError(error: unknown): string {
  const baseMessage = formatError(error)

  // Add helpful context for common network errors
  if (baseMessage.includes('NetworkError') || baseMessage.includes('fetch')) {
    return `Network error: ${baseMessage}. Please check your connection.`
  }
  if (baseMessage.includes('timeout') || baseMessage.includes('ETIMEDOUT')) {
    return `Request timed out: ${baseMessage}. The server may be unavailable.`
  }
  if (baseMessage.includes('ECONNREFUSED')) {
    return `Connection refused: ${baseMessage}. The kdb+ server may not be running.`
  }

  return baseMessage
}

/**
 * Extract error message from kdb+ query result.
 * Handles nested error structures from .u.upd failures.
 */
export function extractKdbQueryError(result: unknown): string {
  if (!result || typeof result !== 'object') {
    return 'Invalid kdb+ query result'
  }

  const resultObj = result as Record<string, unknown>

  // Standard { success, error } pattern
  if ('success' in resultObj && !resultObj.success) {
    return formatKdbError(resultObj as { success: boolean; error?: string })
  }

  // Nested error object
  if ('error' in resultObj) {
    if (typeof resultObj.error === 'string') {
      return resultObj.error
    }
    if (resultObj.error && typeof resultObj.error === 'object') {
      const errorObj = resultObj.error as Record<string, unknown>
      if (errorObj.message && typeof errorObj.message === 'string') {
        return errorObj.message
      }
    }
  }

  return 'Unknown kdb+ error'
}
