import { copyToClipboard, isClipboardSupported } from './clipboard';

describe('clipboard utilities', () => {
  let originalClipboard: Clipboard | undefined;
  let originalExecCommand: typeof document.execCommand;
  let originalQueryCommandSupported: typeof document.queryCommandSupported;
  let originalIsSecureContext: boolean;
  let mockWriteText: jest.Mock;
  let mockAlert: jest.Mock;
  let mockPrompt: jest.Mock;

  beforeEach(() => {
    jest.resetAllMocks();

    // Store originals
    originalClipboard = navigator.clipboard;
    originalExecCommand = document.execCommand;
    originalQueryCommandSupported = document.queryCommandSupported;
    originalIsSecureContext = window.isSecureContext;

    // Set up mocks
    mockWriteText = jest.fn().mockResolvedValue(undefined);
    mockAlert = jest.fn();
    mockPrompt = jest.fn().mockReturnValue('copied text');

    // Mock clipboard API
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText: mockWriteText },
      configurable: true,
      writable: true
    });

    // Mock isSecureContext (required for clipboard API path)
    Object.defineProperty(window, 'isSecureContext', {
      value: true,
      configurable: true,
      writable: true
    });

    // Mock window methods
    global.alert = mockAlert;
    global.prompt = mockPrompt;

    // Mock execCommand
    Object.defineProperty(document, 'execCommand', {
      value: jest.fn().mockReturnValue(true),
      configurable: true,
      writable: true
    });

    Object.defineProperty(document, 'queryCommandSupported', {
      value: jest.fn().mockReturnValue(true),
      configurable: true,
      writable: true
    });
  });

  afterEach(() => {
    // Restore originals
    if (originalClipboard !== undefined) {
      Object.defineProperty(navigator, 'clipboard', {
        value: originalClipboard,
        configurable: true,
        writable: true
      });
    }
    Object.defineProperty(document, 'execCommand', {
      value: originalExecCommand,
      configurable: true,
      writable: true
    });
    Object.defineProperty(document, 'queryCommandSupported', {
      value: originalQueryCommandSupported,
      configurable: true,
      writable: true
    });
    Object.defineProperty(window, 'isSecureContext', {
      value: originalIsSecureContext,
      configurable: true,
      writable: true
    });
  });

  describe('copyToClipboard', () => {
    it('successfully copies text using clipboard API', async () => {
      const testText = 'Hello, World!';

      const result = await copyToClipboard(testText);

      expect(result).toBe(true);
      expect(mockWriteText).toHaveBeenCalledWith(testText);
      expect(mockAlert).toHaveBeenCalledWith('Copied to clipboard!');
    });

    it('copies text without showing alert when disabled', async () => {
      const testText = 'Hello, World!';

      const result = await copyToClipboard(testText, { showAlert: false });

      expect(result).toBe(true);
      expect(mockWriteText).toHaveBeenCalledWith(testText);
      expect(mockAlert).not.toHaveBeenCalled();
    });

    it('shows custom success message when provided', async () => {
      const testText = 'Hello, World!';
      const customMessage = 'Custom success message!';

      const result = await copyToClipboard(testText, {
        successMessage: customMessage
      });

      expect(result).toBe(true);
      expect(mockAlert).toHaveBeenCalledWith(customMessage);
    });

    it('falls back to execCommand when clipboard API fails', async () => {
      mockWriteText.mockRejectedValue(new Error('Clipboard API failed'));

      const testText = 'Fallback test';
      const result = await copyToClipboard(testText);

      expect(result).toBe(true);
      expect(document.execCommand).toHaveBeenCalledWith('copy');
    });

    it('handles empty text correctly', async () => {
      const result = await copyToClipboard('');

      expect(result).toBe(true);
      expect(mockWriteText).toHaveBeenCalledWith('');
    });

    it('handles special characters and unicode', async () => {
      const testText = '特殊文字 🚀 emoji & symbols!@#$%^&*()';

      const result = await copyToClipboard(testText);

      expect(result).toBe(true);
      expect(mockWriteText).toHaveBeenCalledWith(testText);
    });

    it('uses execCommand fallback when clipboard is unavailable', async () => {
      // Disable clipboard API for this test
      Object.defineProperty(navigator, 'clipboard', {
        value: undefined,
        configurable: true,
        writable: true
      });

      const testText = 'Fallback test';
      const result = await copyToClipboard(testText);

      expect(result).toBe(true);
      expect(document.execCommand).toHaveBeenCalledWith('copy');
    });

    it('falls back to prompt when execCommand fails', async () => {
      Object.defineProperty(navigator, 'clipboard', {
        value: undefined,
        configurable: true,
        writable: true
      });
      (document.execCommand as jest.Mock).mockReturnValue(false);
      mockPrompt.mockReturnValue('user copied');

      const testText = 'Failed copy test';
      const result = await copyToClipboard(testText);

      expect(result).toBe(true);
      expect(mockPrompt).toHaveBeenCalledWith(
        'Unable to copy automatically. Please copy this text manually:',
        testText
      );
    });

    it('returns false when user cancels manual copy prompt', async () => {
      Object.defineProperty(navigator, 'clipboard', {
        value: undefined,
        configurable: true,
        writable: true
      });
      (document.execCommand as jest.Mock).mockReturnValue(false);
      mockPrompt.mockReturnValue(null);

      const testText = 'Cancelled copy test';
      const result = await copyToClipboard(testText, { showAlert: false });

      expect(result).toBe(false);
      expect(mockAlert).not.toHaveBeenCalled();
    });
  });

  describe('isClipboardSupported', () => {
    it('returns true when clipboard API is available', () => {
      expect(isClipboardSupported()).toBe(true);
    });

    it('returns true when execCommand copy is supported', () => {
      Object.defineProperty(navigator, 'clipboard', {
        value: undefined,
        configurable: true,
        writable: true
      });
      (document.queryCommandSupported as jest.Mock).mockReturnValue(true);

      expect(isClipboardSupported()).toBe(true);
      expect(document.queryCommandSupported).toHaveBeenCalledWith('copy');
    });

    it('returns false when no clipboard methods are available', () => {
      Object.defineProperty(navigator, 'clipboard', {
        value: undefined,
        configurable: true,
        writable: true
      });
      (document.queryCommandSupported as jest.Mock).mockReturnValue(false);

      expect(isClipboardSupported()).toBe(false);
    });
  });
});
