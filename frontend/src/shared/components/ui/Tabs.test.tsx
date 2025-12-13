import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { Tabs, TabsList, TabsTrigger, TabsContent } from './Tabs';

describe('Tabs', () => {
  const renderTabs = (props: Partial<React.ComponentProps<typeof Tabs>> = {}) => {
    return render(
      <Tabs defaultValue="tab1" {...props}>
        <TabsList>
          <TabsTrigger value="tab1">Tab 1</TabsTrigger>
          <TabsTrigger value="tab2">Tab 2</TabsTrigger>
          <TabsTrigger value="tab3">Tab 3</TabsTrigger>
        </TabsList>
        <TabsContent value="tab1">Content 1</TabsContent>
        <TabsContent value="tab2">Content 2</TabsContent>
        <TabsContent value="tab3">Content 3</TabsContent>
      </Tabs>
    );
  };

  describe('rendering', () => {
    it('renders tab triggers', () => {
      renderTabs();

      expect(screen.getByText('Tab 1')).toBeInTheDocument();
      expect(screen.getByText('Tab 2')).toBeInTheDocument();
      expect(screen.getByText('Tab 3')).toBeInTheDocument();
    });

    it('renders default tab content', () => {
      renderTabs();

      expect(screen.getByText('Content 1')).toBeInTheDocument();
    });

    it('does not render inactive tab content', () => {
      renderTabs();

      expect(screen.queryByText('Content 2')).not.toBeInTheDocument();
      expect(screen.queryByText('Content 3')).not.toBeInTheDocument();
    });

    it('applies custom className to Tabs', () => {
      const { container } = renderTabs({ className: 'custom-tabs' });

      expect(container.querySelector('.custom-tabs')).toBeInTheDocument();
    });
  });

  describe('tab switching', () => {
    it('switches tab content when clicking trigger', () => {
      renderTabs();

      fireEvent.click(screen.getByText('Tab 2'));

      expect(screen.getByText('Content 2')).toBeInTheDocument();
      expect(screen.queryByText('Content 1')).not.toBeInTheDocument();
    });

    it('switches to third tab', () => {
      renderTabs();

      fireEvent.click(screen.getByText('Tab 3'));

      expect(screen.getByText('Content 3')).toBeInTheDocument();
      expect(screen.queryByText('Content 1')).not.toBeInTheDocument();
      expect(screen.queryByText('Content 2')).not.toBeInTheDocument();
    });

    it('switches back to first tab', () => {
      renderTabs();

      // Switch to tab 2
      fireEvent.click(screen.getByText('Tab 2'));
      expect(screen.getByText('Content 2')).toBeInTheDocument();

      // Switch back to tab 1
      fireEvent.click(screen.getByText('Tab 1'));
      expect(screen.getByText('Content 1')).toBeInTheDocument();
      expect(screen.queryByText('Content 2')).not.toBeInTheDocument();
    });
  });

  describe('controlled mode', () => {
    it('uses controlled value when provided', () => {
      render(
        <Tabs value="tab2" onValueChange={jest.fn()}>
          <TabsList>
            <TabsTrigger value="tab1">Tab 1</TabsTrigger>
            <TabsTrigger value="tab2">Tab 2</TabsTrigger>
          </TabsList>
          <TabsContent value="tab1">Content 1</TabsContent>
          <TabsContent value="tab2">Content 2</TabsContent>
        </Tabs>
      );

      expect(screen.getByText('Content 2')).toBeInTheDocument();
      expect(screen.queryByText('Content 1')).not.toBeInTheDocument();
    });

    it('calls onValueChange when tab is clicked', () => {
      const onValueChange = jest.fn();
      render(
        <Tabs value="tab1" onValueChange={onValueChange}>
          <TabsList>
            <TabsTrigger value="tab1">Tab 1</TabsTrigger>
            <TabsTrigger value="tab2">Tab 2</TabsTrigger>
          </TabsList>
          <TabsContent value="tab1">Content 1</TabsContent>
          <TabsContent value="tab2">Content 2</TabsContent>
        </Tabs>
      );

      fireEvent.click(screen.getByText('Tab 2'));

      expect(onValueChange).toHaveBeenCalledWith('tab2');
    });
  });

  describe('active tab styling', () => {
    it('applies active styling to current tab trigger', () => {
      renderTabs();

      const tab1Button = screen.getByText('Tab 1').closest('button');
      expect(tab1Button).toHaveClass('border-theme-interactive-primary', 'text-theme-interactive-primary');
    });

    it('applies inactive styling to other tab triggers', () => {
      renderTabs();

      const tab2Button = screen.getByText('Tab 2').closest('button');
      expect(tab2Button).toHaveClass('border-transparent', 'text-theme-muted');
    });

    it('updates styling when tab changes', () => {
      renderTabs();

      fireEvent.click(screen.getByText('Tab 2'));

      const tab1Button = screen.getByText('Tab 1').closest('button');
      const tab2Button = screen.getByText('Tab 2').closest('button');

      expect(tab2Button).toHaveClass('border-theme-interactive-primary');
      expect(tab1Button).toHaveClass('border-transparent');
    });
  });

  describe('TabsList', () => {
    it('renders with proper styling', () => {
      renderTabs();

      const tabsList = screen.getByText('Tab 1').closest('div');
      expect(tabsList).toHaveClass('flex', 'border-b', 'border-theme-border', 'bg-theme-surface');
    });

    it('applies custom className', () => {
      render(
        <Tabs defaultValue="tab1">
          <TabsList className="custom-list">
            <TabsTrigger value="tab1">Tab 1</TabsTrigger>
          </TabsList>
          <TabsContent value="tab1">Content</TabsContent>
        </Tabs>
      );

      const tabsList = screen.getByText('Tab 1').closest('div');
      expect(tabsList).toHaveClass('custom-list');
    });
  });

  describe('TabsTrigger', () => {
    it('renders as button', () => {
      renderTabs();

      const buttons = screen.getAllByRole('button');
      expect(buttons.length).toBe(3);
    });

    it('has type button to prevent form submission', () => {
      renderTabs();

      const button = screen.getByText('Tab 1').closest('button');
      expect(button).toHaveAttribute('type', 'button');
    });

    it('applies custom className', () => {
      render(
        <Tabs defaultValue="tab1">
          <TabsList>
            <TabsTrigger value="tab1" className="custom-trigger">Tab 1</TabsTrigger>
          </TabsList>
          <TabsContent value="tab1">Content</TabsContent>
        </Tabs>
      );

      const button = screen.getByText('Tab 1').closest('button');
      expect(button).toHaveClass('custom-trigger');
    });

    it('has proper transition styling', () => {
      renderTabs();

      const button = screen.getByText('Tab 1').closest('button');
      expect(button).toHaveClass('transition-colors', 'duration-200');
    });
  });

  describe('TabsContent', () => {
    it('applies custom className', () => {
      render(
        <Tabs defaultValue="tab1">
          <TabsList>
            <TabsTrigger value="tab1">Tab 1</TabsTrigger>
          </TabsList>
          <TabsContent value="tab1" className="custom-content">
            <span>Content</span>
          </TabsContent>
        </Tabs>
      );

      const content = screen.getByText('Content');
      expect(content.closest('.custom-content')).toBeInTheDocument();
    });

    it('has margin top for spacing', () => {
      render(
        <Tabs defaultValue="tab1">
          <TabsList>
            <TabsTrigger value="tab1">Tab 1</TabsTrigger>
          </TabsList>
          <TabsContent value="tab1">
            <span>Content</span>
          </TabsContent>
        </Tabs>
      );

      const content = screen.getByText('Content');
      expect(content.closest('.mt-4')).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    it('throws error when TabsTrigger used outside Tabs', () => {
      // Suppress console.error for this test
      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

      expect(() => {
        render(<TabsTrigger value="tab1">Tab 1</TabsTrigger>);
      }).toThrow('TabsTrigger must be used within a Tabs component');

      consoleSpy.mockRestore();
    });

    it('throws error when TabsContent used outside Tabs', () => {
      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

      expect(() => {
        render(<TabsContent value="tab1">Content</TabsContent>);
      }).toThrow('TabsContent must be used within a Tabs component');

      consoleSpy.mockRestore();
    });
  });
});
