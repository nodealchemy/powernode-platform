/**
 * Utility function for copying text to clipboard with fallback support
 * Handles both modern Clipboard API and legacy document.execCommand
 */
export const copyToClipboard = async (text: string, options?: {
  showAlert?: boolean;
  successMessage?: string;
  errorMessage?: string;
}): Promise<boolean> => {
  const {
    showAlert = true,
    successMessage = 'Copied to clipboard!',
    // errorMessage = 'Failed to copy to clipboard'
  } = options || {};

  try {
    // Try modern clipboard API first (requires HTTPS)
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      if (showAlert) {
        alert(successMessage);
      }
      return true;
    } else {
      // Fallback for older browsers or non-HTTPS contexts
      const textArea = document.createElement('textarea');
      textArea.value = text;
      
      // Make the textarea invisible and position it off-screen
      textArea.style.position = 'fixed';
      textArea.style.left = '-999999px';
      textArea.style.top = '-999999px';
      textArea.style.opacity = '0';
      textArea.style.pointerEvents = 'none';
      textArea.readOnly = true;
      
      document.body.appendChild(textArea);
      
      // Select and copy the text
      textArea.focus();
      textArea.select();
      textArea.setSelectionRange(0, text.length);
      
      const successful = document.execCommand('copy');
      document.body.removeChild(textArea);
      
      if (successful) {
        if (showAlert) {
          alert(successMessage);
        }
        return true;
      } else {
        throw new Error('Copy command failed');
      }
    }
  } catch (error) {
    console.error('Failed to copy to clipboard:', error);
    
    // Last resort: show the text in a prompt for manual copying
    const result = window.prompt('Unable to copy automatically. Please copy this text manually:', text);
    
    // If user didn't cancel the prompt, consider it a success
    if (result !== null && showAlert) {
      alert('Please copy the text manually from the dialog');
    }
    
    return result !== null;
  }
};

/**
 * Check if clipboard functionality is available
 */
export const isClipboardSupported = (): boolean => {
  return !!(navigator.clipboard && window.isSecureContext) || 
         !!(document.queryCommandSupported && document.queryCommandSupported('copy'));
};