/**
 * DOM Error Handler - Handles browser extension and autofill overlay errors
 */

/**
 * Handles common DOM manipulation errors from browser extensions
 */
export const handleDOMErrors = (): void => {
  // Handle unhandled promise rejections (including DOM insertion errors)
  window.addEventListener('unhandledrejection', (event) => {
    const error = event.reason;
    
    // Check if it's a DOM-related error from browser extensions
    if (error && error.message && typeof error.message === 'string') {
      const message = error.message.toLowerCase();
      
      // Common browser extension DOM errors
      const extensionErrors = [
        'failed to execute \'insertbefore\' on \'node\'',
        'the node before which the new node is to be inserted is not a child',
        'autofill-inline-menu',
        'bootstrap-autofill-overlay',
        'extension context invalidated',
        'disconnected port object'
      ];
      
      if (extensionErrors.some(pattern => message.includes(pattern))) {
        if (process.env.NODE_ENV === 'development') {
          console.warn('[DOM] Browser extension DOM error suppressed:', error.message);
        }
        event.preventDefault(); // Suppress the error
        return;
      }
    }
    
    // Let other errors through normally
  });

  // Handle general errors
  window.addEventListener('error', (event) => {
    const error = event.error;
    
    if (error && error.message && typeof error.message === 'string') {
      const message = error.message.toLowerCase();
      
      // Suppress known browser extension errors
      if (message.includes('extension context invalidated') ||
          message.includes('bootstrap-autofill-overlay') ||
          message.includes('autofill-inline-menu')) {
        if (process.env.NODE_ENV === 'development') {
          console.warn('[DOM] Browser extension error suppressed:', error.message);
        }
        event.preventDefault();
        return;
      }
    }
  });
};

/**
 * Defensive form field setup to prevent extension conflicts
 */
export const setupFormDefenses = (): void => {
  // Add defensive attributes to forms to minimize extension conflicts
  const observer = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      mutation.addedNodes.forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const element = node as Element;
          
          // Add defensive attributes to input fields
          const inputs = element.querySelectorAll('input[type="email"], input[type="password"], input[type="text"]');
          inputs.forEach((input) => {
            const inputElement = input as HTMLInputElement;
            
            // Add attributes that can help reduce extension conflicts
            if (!inputElement.hasAttribute('data-form-type')) {
              inputElement.setAttribute('data-form-type', inputElement.type);
            }
            
            // Add autocomplete attributes if missing
            if (!inputElement.hasAttribute('autocomplete')) {
              switch (inputElement.type) {
                case 'email':
                  inputElement.setAttribute('autocomplete', 'username');
                  break;
                case 'password':
                  inputElement.setAttribute('autocomplete', 'current-password');
                  break;
                default:
                  inputElement.setAttribute('autocomplete', 'off');
              }
            }
          });
        }
      });
    });
  });

  // Observe the entire document for form additions
  observer.observe(document.body, {
    childList: true,
    subtree: true
  });

  // Disconnect after 30 seconds - form defenses only needed during initial page load
  setTimeout(() => {
    observer.disconnect();
  }, 30000);
};

/**
 * Initialize DOM error handling
 */
export const initializeDOMErrorHandling = (): void => {
  handleDOMErrors();
  
  // Setup form defenses when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupFormDefenses);
  } else {
    setupFormDefenses();
  }
};