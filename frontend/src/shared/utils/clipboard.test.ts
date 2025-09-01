import { copyToClipboard, isClipboardSupported } from './clipboard';

// Mock global objects and methods
const mockNavigator = {
  clipboard: {
    writeText: jest.fn()
  }
};

const mockWindow = {
  isSecureContext: true,
  prompt: jest.fn(),
  alert: jest.fn()
};

const mockDocument = {
  createElement: jest.fn(),
  body: {
    appendChild: jest.fn(),
    removeChild: jest.fn()
  },
  execCommand: jest.fn(),
  queryCommandSupported: jest.fn()
};

describe('clipboard utilities', () => {
  let originalNavigator: any;
  let originalWindow: any;
  let originalDocument: any;

  beforeEach(() => {
    // Store original objects
    originalNavigator = global.navigator;
    originalWindow = global.window;
    originalDocument = global.document;

    // Reset mocks
    jest.clearAllMocks();
    
    // Set up default successful mocks
    mockNavigator.clipboard.writeText.mockResolvedValue(undefined);
    mockWindow.prompt.mockReturnValue('copied text');
    mockWindow.alert.mockImplementation(() => {});
    mockDocument.createElement.mockReturnValue({
      value: '',
      style: {},
      focus: jest.fn(),
      select: jest.fn(),
      setSelectionRange: jest.fn(),
      readOnly: false
    });
    mockDocument.execCommand.mockReturnValue(true);
    mockDocument.queryCommandSupported.mockReturnValue(true);

    // Apply mocks
    Object.defineProperty(global, 'navigator', {
      value: mockNavigator,
      configurable: true
    });
    Object.defineProperty(global, 'window', {
      value: mockWindow,
      configurable: true
    });
    Object.defineProperty(global, 'document', {
      value: mockDocument,
      configurable: true
    });
    
    // Mock global alert function
    global.alert = mockWindow.alert;
  });

  afterEach(() => {
    // Restore original objects
    Object.defineProperty(global, 'navigator', {
      value: originalNavigator,
      configurable: true
    });
    Object.defineProperty(global, 'window', {
      value: originalWindow,
      configurable: true
    });
    Object.defineProperty(global, 'document', {
      value: originalDocument,
      configurable: true
    });
  });

  describe('copyToClipboard', () => {
    describe('modern clipboard API', () => {
      it('successfully copies text using clipboard API', async () => {
        const testText = 'Hello, World!';
        
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockNavigator.clipboard.writeText).toHaveBeenCalledWith(testText);
        expect(mockWindow.alert).toHaveBeenCalledWith('Copied to clipboard!');
      });

      it('copies text without showing alert when disabled', async () => {
        const testText = 'Hello, World!';
        
        const result = await copyToClipboard(testText, { showAlert: false });
        
        expect(result).toBe(true);
        expect(mockNavigator.clipboard.writeText).toHaveBeenCalledWith(testText);
        expect(mockWindow.alert).not.toHaveBeenCalled();
      });

      it('shows custom success message when provided', async () => {
        const testText = 'Hello, World!';
        const customMessage = 'Custom success message!';
        
        const result = await copyToClipboard(testText, { 
          successMessage: customMessage 
        });
        
        expect(result).toBe(true);
        expect(mockWindow.alert).toHaveBeenCalledWith(customMessage);
      });

      it('falls back to execCommand when clipboard API fails', async () => {
        mockNavigator.clipboard.writeText.mockRejectedValue(new Error('Clipboard API failed'));
        
        const testText = 'Fallback test';
        const mockTextArea = {
          value: '',
          style: {},
          focus: jest.fn(),
          select: jest.fn(),
          setSelectionRange: jest.fn(),
          readOnly: false
        };
        
        mockDocument.createElement.mockReturnValue(mockTextArea);
        mockDocument.execCommand.mockReturnValue(true);
        
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockDocument.createElement).toHaveBeenCalledWith('textarea');
        expect(mockTextArea.value).toBe(testText);
        expect(mockDocument.execCommand).toHaveBeenCalledWith('copy');
        expect(mockDocument.body.appendChild).toHaveBeenCalledWith(mockTextArea);
        expect(mockDocument.body.removeChild).toHaveBeenCalledWith(mockTextArea);
      });
    });

    describe('fallback execCommand method', () => {
      beforeEach(() => {
        // Disable clipboard API
        Object.defineProperty(global, 'navigator', {
          value: { clipboard: null },
          configurable: true
        });
        Object.defineProperty(global, 'window', {
          value: { ...mockWindow, isSecureContext: false },
          configurable: true
        });
      });

      it('successfully copies text using execCommand fallback', async () => {
        const testText = 'Fallback test';
        const mockTextArea = {
          value: '',
          style: {},
          focus: jest.fn(),
          select: jest.fn(),
          setSelectionRange: jest.fn(),
          readOnly: false
        };
        
        mockDocument.createElement.mockReturnValue(mockTextArea);
        mockDocument.execCommand.mockReturnValue(true);
        
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockTextArea.value).toBe(testText);
        expect(mockTextArea.style.position).toBe('fixed');
        expect(mockTextArea.style.left).toBe('-999999px');
        expect(mockTextArea.style.top).toBe('-999999px');
        expect(mockTextArea.style.opacity).toBe('0');
        expect(mockTextArea.style.pointerEvents).toBe('none');
        expect(mockTextArea.readOnly).toBe(true);
        
        expect(mockTextArea.focus).toHaveBeenCalled();
        expect(mockTextArea.select).toHaveBeenCalled();
        expect(mockTextArea.setSelectionRange).toHaveBeenCalledWith(0, testText.length);
        expect(mockDocument.execCommand).toHaveBeenCalledWith('copy');
      });

      it('handles execCommand failure and falls back to prompt', async () => {
        const testText = 'Failed copy test';
        const mockTextArea = {
          value: '',
          style: {},
          focus: jest.fn(),
          select: jest.fn(),
          setSelectionRange: jest.fn(),
          readOnly: false
        };
        
        mockDocument.createElement.mockReturnValue(mockTextArea);
        mockDocument.execCommand.mockReturnValue(false);
        mockWindow.prompt.mockReturnValue('user copied');
        
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockWindow.prompt).toHaveBeenCalledWith(
          'Unable to copy automatically. Please copy this text manually:',
          testText
        );
        expect(mockWindow.alert).toHaveBeenCalledWith('Please copy the text manually from the dialog');
      });

      it('returns false when user cancels manual copy prompt', async () => {
        const testText = 'Cancelled copy test';
        
        mockDocument.execCommand.mockReturnValue(false);
        mockWindow.prompt.mockReturnValue(null); // User cancelled
        
        const result = await copyToClipboard(testText, { showAlert: false });
        
        expect(result).toBe(false);
        expect(mockWindow.alert).not.toHaveBeenCalled();
      });
    });

    describe('error handling', () => {
      it('handles clipboard API errors gracefully', async () => {
        mockNavigator.clipboard.writeText.mockRejectedValue(new Error('Security error'));
        mockDocument.execCommand.mockImplementation(() => {
          throw new Error('ExecCommand failed');
        });
        mockWindow.prompt.mockReturnValue('manual copy');
        
        const testText = 'Error test';
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockWindow.prompt).toHaveBeenCalledWith(
          'Unable to copy automatically. Please copy this text manually:',
          testText
        );
      });

      it('handles DOM manipulation errors', async () => {
        Object.defineProperty(global, 'navigator', {
          value: { clipboard: null },
          configurable: true
        });
        
        mockDocument.createElement.mockImplementation(() => {
          throw new Error('DOM error');
        });
        mockWindow.prompt.mockReturnValue('fallback copy');
        
        const testText = 'DOM error test';
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockWindow.prompt).toHaveBeenCalled();
      });

      it('handles empty text correctly', async () => {
        const result = await copyToClipboard('');
        
        expect(result).toBe(true);
        expect(mockNavigator.clipboard.writeText).toHaveBeenCalledWith('');
      });

      it('handles special characters and unicode', async () => {
        const testText = '特殊文字 🚀 emoji & symbols!@#$%^&*()';
        
        const result = await copyToClipboard(testText);
        
        expect(result).toBe(true);
        expect(mockNavigator.clipboard.writeText).toHaveBeenCalledWith(testText);
      });

      it('handles very long text', async () => {
        const longText = 'A'.repeat(100000);
        
        const result = await copyToClipboard(longText);
        
        expect(result).toBe(true);
        expect(mockNavigator.clipboard.writeText).toHaveBeenCalledWith(longText);
      });
    });

    describe('options handling', () => {
      it('handles undefined options gracefully', async () => {
        const testText = 'Options test';
        
        const result = await copyToClipboard(testText, undefined);
        
        expect(result).toBe(true);
        expect(mockWindow.alert).toHaveBeenCalledWith('Copied to clipboard!');
      });

      it('handles partial options object', async () => {
        const testText = 'Partial options test';
        
        const result = await copyToClipboard(testText, { showAlert: true });
        
        expect(result).toBe(true);
        expect(mockWindow.alert).toHaveBeenCalledWith('Copied to clipboard!');
      });

      it('handles custom error message option', async () => {
        // Note: The current implementation doesn't use errorMessage,
        // but we should test that it doesn't break when provided
        const testText = 'Error message test';
        
        const result = await copyToClipboard(testText, {
          errorMessage: 'Custom error message'
        });
        
        expect(result).toBe(true);
      });
    });
  });

  describe('isClipboardSupported', () => {
    it('returns true when clipboard API is available in secure context', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: { writeText: jest.fn() } },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: true },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(true);
    });

    it('returns false when clipboard API is available but not in secure context', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: { writeText: jest.fn() } },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: false },
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: jest.fn().mockReturnValue(false) },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(false);
    });

    it('returns true when execCommand copy is supported', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: null },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: false },
        configurable: true
      });
      const queryCommandSupported = jest.fn().mockReturnValue(true);
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(true);
      expect(queryCommandSupported).toHaveBeenCalledWith('copy');
    });

    it('returns false when no clipboard methods are available', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: null },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: false },
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: null },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(false);
    });

    it('returns false when queryCommandSupported returns false', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: null },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: false },
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: jest.fn().mockReturnValue(false) },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(false);
    });

    it('handles missing navigator object', () => {
      Object.defineProperty(global, 'navigator', {
        value: undefined,
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: jest.fn().mockReturnValue(true) },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(true);
    });

    it('handles missing window object', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: { writeText: jest.fn() } },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: undefined,
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: jest.fn().mockReturnValue(true) },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(true);
    });
  });

  describe('edge cases and browser compatibility', () => {
    it('handles Internet Explorer compatibility', () => {
      // Simulate IE environment
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: undefined },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: undefined },
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: jest.fn().mockReturnValue(true) },
        configurable: true
      });
      
      expect(isClipboardSupported()).toBe(true);
    });

    it('handles Firefox compatibility', async () => {
      // Simulate Firefox with clipboard API but without secure context
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: { writeText: jest.fn().mockRejectedValue(new Error('NotAllowedError')) } },
        configurable: true
      });
      
      const testText = 'Firefox test';
      const mockTextArea = {
        value: '',
        style: {},
        focus: jest.fn(),
        select: jest.fn(),
        setSelectionRange: jest.fn(),
        readOnly: false
      };
      
      mockDocument.createElement.mockReturnValue(mockTextArea);
      mockDocument.execCommand.mockReturnValue(true);
      
      const result = await copyToClipboard(testText);
      
      expect(result).toBe(true);
      expect(mockDocument.execCommand).toHaveBeenCalledWith('copy');
    });

    it('handles mobile browser limitations', async () => {
      // Simulate mobile browser environment
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: null },
        configurable: true
      });
      mockDocument.execCommand.mockReturnValue(false);
      mockWindow.prompt.mockReturnValue('mobile copy');
      
      const testText = 'Mobile test';
      const result = await copyToClipboard(testText);
      
      expect(result).toBe(true);
      expect(mockWindow.prompt).toHaveBeenCalled();
    });
  });

  describe('security considerations', () => {
    it('handles HTTPS requirement for clipboard API', () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: { writeText: jest.fn() } },
        configurable: true
      });
      Object.defineProperty(global, 'window', {
        value: { isSecureContext: false },
        configurable: true
      });
      Object.defineProperty(global, 'document', {
        value: { queryCommandSupported: jest.fn().mockReturnValue(true) },
        configurable: true
      });
      
      // Should fall back to execCommand when not in secure context
      expect(isClipboardSupported()).toBe(true);
    });

    it('sanitizes textarea elements properly', async () => {
      Object.defineProperty(global, 'navigator', {
        value: { clipboard: null },
        configurable: true
      });
      
      const testText = '<script>alert("xss")</script>';
      const mockTextArea = {
        value: '',
        style: {},
        focus: jest.fn(),
        select: jest.fn(),
        setSelectionRange: jest.fn(),
        readOnly: false
      };
      
      mockDocument.createElement.mockReturnValue(mockTextArea);
      mockDocument.execCommand.mockReturnValue(true);
      
      await copyToClipboard(testText);
      
      // Should set the value as-is (browser handles safety)
      expect(mockTextArea.value).toBe(testText);
      expect(mockTextArea.readOnly).toBe(true);
      expect(mockTextArea.style.pointerEvents).toBe('none');
    });
  });
});