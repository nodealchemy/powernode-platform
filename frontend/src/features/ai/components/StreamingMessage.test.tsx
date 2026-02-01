import { render, screen } from '@testing-library/react';
import { StreamingMessage } from './StreamingMessage';

describe('StreamingMessage', () => {
  describe('when streaming', () => {
    it('renders content with streaming cursor', () => {
      render(
        <StreamingMessage
          content="Hello, I am"
          isStreaming={true}
        />
      );

      expect(screen.getByText(/Hello, I am/)).toBeInTheDocument();
      // Cursor should be present (animated element)
      const cursor = document.querySelector('.animate-pulse');
      expect(cursor).toBeInTheDocument();
    });

    it('shows loading indicator when no content yet', () => {
      render(
        <StreamingMessage
          content=""
          isStreaming={true}
        />
      );

      expect(screen.getByText(/AI is thinking/i)).toBeInTheDocument();
    });

    it('displays metrics when showMetrics is true', () => {
      render(
        <StreamingMessage
          content="Test content"
          isStreaming={true}
          tokenCount={50}
          elapsedMs={1500}
          showMetrics={true}
        />
      );

      expect(screen.getByText(/50 tokens/)).toBeInTheDocument();
      expect(screen.getByText(/1.5s/)).toBeInTheDocument();
      expect(screen.getByText(/Streaming/i)).toBeInTheDocument();
    });
  });

  describe('when not streaming', () => {
    it('renders markdown content after streaming completes', () => {
      render(
        <StreamingMessage
          content="**Bold text** and *italic*"
          isStreaming={false}
        />
      );

      // ReactMarkdown mock renders raw content
      expect(screen.getByTestId('react-markdown')).toBeInTheDocument();
      expect(screen.getByText(/Bold text/)).toBeInTheDocument();
    });

    it('does not show cursor when streaming is complete', () => {
      render(
        <StreamingMessage
          content="Complete response"
          isStreaming={false}
        />
      );

      const cursor = document.querySelector('.animate-pulse');
      expect(cursor).not.toBeInTheDocument();
    });

    it('returns null when no content and not streaming', () => {
      const { container } = render(
        <StreamingMessage
          content=""
          isStreaming={false}
        />
      );

      expect(container.firstChild).toBeNull();
    });
  });

  describe('error state', () => {
    it('displays error message', () => {
      render(
        <StreamingMessage
          content=""
          isStreaming={false}
          error="Connection lost"
        />
      );

      expect(screen.getByText('Connection lost')).toBeInTheDocument();
    });

    it('applies error styling', () => {
      render(
        <StreamingMessage
          content=""
          isStreaming={false}
          error="Error occurred"
        />
      );

      const errorContainer = screen.getByText('Error occurred').parentElement;
      expect(errorContainer).toHaveClass('bg-theme-danger/10');
    });
  });

  describe('metrics display', () => {
    it('shows all metrics when provided', () => {
      render(
        <StreamingMessage
          content="Test"
          isStreaming={false}
          tokenCount={100}
          elapsedMs={2500}
          showMetrics={true}
        />
      );

      expect(screen.getByText(/100 tokens/)).toBeInTheDocument();
      expect(screen.getByText(/2.5s/)).toBeInTheDocument();
    });

    it('hides metrics when showMetrics is false', () => {
      render(
        <StreamingMessage
          content="Test"
          isStreaming={false}
          tokenCount={100}
          elapsedMs={2500}
          showMetrics={false}
        />
      );

      expect(screen.queryByText(/100 tokens/)).not.toBeInTheDocument();
    });
  });

  describe('className prop', () => {
    it('applies custom className', () => {
      const { container } = render(
        <StreamingMessage
          content="Test"
          isStreaming={false}
          className="custom-class"
        />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });
});
