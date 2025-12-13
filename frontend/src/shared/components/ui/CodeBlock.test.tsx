import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import CodeBlock from './CodeBlock';

// Mock clipboard API
const mockWriteText = jest.fn();
Object.assign(navigator, {
  clipboard: {
    writeText: mockWriteText
  }
});

describe('CodeBlock', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockWriteText.mockResolvedValue(undefined);
  });

  describe('rendering', () => {
    it('renders code content', () => {
      render(<CodeBlock code="const x = 1;" />);

      expect(screen.getByText('const x = 1;')).toBeInTheDocument();
    });

    it('renders code in pre and code elements', () => {
      const { container } = render(<CodeBlock code="test code" />);

      expect(container.querySelector('pre')).toBeInTheDocument();
      expect(container.querySelector('code')).toBeInTheDocument();
    });

    it('displays language label', () => {
      render(<CodeBlock code="{}" language="json" />);

      expect(screen.getByText('json')).toBeInTheDocument();
    });

    it('defaults to json language', () => {
      render(<CodeBlock code="{}" />);

      expect(screen.getByText('json')).toBeInTheDocument();
    });

    it('shows copy button by default', () => {
      render(<CodeBlock code="test" />);

      expect(screen.getByText('Copy')).toBeInTheDocument();
    });
  });

  describe('copy functionality', () => {
    it('copies code to clipboard when copy button clicked', async () => {
      const code = 'const x = 42;';
      render(<CodeBlock code={code} />);

      fireEvent.click(screen.getByText('Copy'));

      expect(mockWriteText).toHaveBeenCalledWith(code);
    });

    it('shows "Copied" after successful copy', async () => {
      render(<CodeBlock code="test" />);

      fireEvent.click(screen.getByText('Copy'));

      await waitFor(() => {
        expect(screen.getByText('Copied')).toBeInTheDocument();
      });
    });

    it('reverts to "Copy" after timeout', async () => {
      jest.useFakeTimers();
      render(<CodeBlock code="test" />);

      fireEvent.click(screen.getByText('Copy'));

      await waitFor(() => {
        expect(screen.getByText('Copied')).toBeInTheDocument();
      });

      jest.advanceTimersByTime(2000);

      await waitFor(() => {
        expect(screen.getByText('Copy')).toBeInTheDocument();
      });

      jest.useRealTimers();
    });

    it('handles clipboard error gracefully', async () => {
      mockWriteText.mockRejectedValue(new Error('Clipboard error'));
      render(<CodeBlock code="test" />);

      // Should not throw
      fireEvent.click(screen.getByText('Copy'));

      // Button should still show "Copy" (didn't switch to Copied)
      await waitFor(() => {
        expect(screen.getByText('Copy')).toBeInTheDocument();
      });
    });
  });

  describe('showCopy prop', () => {
    it('hides copy button when showCopy is false', () => {
      render(<CodeBlock code="test" showCopy={false} />);

      expect(screen.queryByText('Copy')).not.toBeInTheDocument();
    });

    it('hides language label when showCopy is false', () => {
      render(<CodeBlock code="test" language="javascript" showCopy={false} />);

      expect(screen.queryByText('javascript')).not.toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('has theme styling classes', () => {
      const { container } = render(<CodeBlock code="test" />);

      const codeContainer = container.querySelector('.bg-theme-background');
      expect(codeContainer).toBeInTheDocument();
    });

    it('has border and rounded corners', () => {
      const { container } = render(<CodeBlock code="test" />);

      const wrapper = container.querySelector('.border');
      expect(wrapper).toHaveClass('border-theme', 'rounded-lg');
    });

    it('code has monospace font', () => {
      const { container } = render(<CodeBlock code="test" />);

      expect(container.querySelector('code')).toHaveClass('font-mono');
    });
  });
});
