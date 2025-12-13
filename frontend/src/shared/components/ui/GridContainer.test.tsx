import { render, screen } from '@testing-library/react';
import { GridContainer, GridCols2, GridCols3, GridCols4, GridAutoFit } from './GridContainer';

describe('GridContainer', () => {
  describe('rendering', () => {
    it('renders children', () => {
      render(
        <GridContainer>
          <div>Item 1</div>
          <div>Item 2</div>
        </GridContainer>
      );

      expect(screen.getByText('Item 1')).toBeInTheDocument();
      expect(screen.getByText('Item 2')).toBeInTheDocument();
    });

    it('renders as div by default', () => {
      const { container } = render(
        <GridContainer>Content</GridContainer>
      );

      expect(container.firstChild?.nodeName).toBe('DIV');
    });

    it('renders as custom element', () => {
      const { container } = render(
        <GridContainer as="section">Content</GridContainer>
      );

      expect(container.firstChild?.nodeName).toBe('SECTION');
    });

    it('applies custom className', () => {
      const { container } = render(
        <GridContainer className="custom-class">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('grid display', () => {
    it('has grid class', () => {
      const { container } = render(
        <GridContainer>Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid');
    });
  });

  describe('columns', () => {
    it('renders 1 column by default', () => {
      const { container } = render(
        <GridContainer>Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-1');
    });

    it('renders 2 columns', () => {
      const { container } = render(
        <GridContainer cols="2">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-2');
    });

    it('renders 3 columns', () => {
      const { container } = render(
        <GridContainer cols="3">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-3');
    });

    it('renders 4 columns', () => {
      const { container } = render(
        <GridContainer cols="4">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-4');
    });

    it('renders 12 columns', () => {
      const { container } = render(
        <GridContainer cols="12">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-12');
    });
  });

  describe('rows', () => {
    it('renders specified rows', () => {
      const { container } = render(
        <GridContainer rows="3">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-rows-3');
    });
  });

  describe('gap', () => {
    it('has medium gap by default', () => {
      const { container } = render(
        <GridContainer>Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('gap-4');
    });

    it('renders no gap', () => {
      const { container } = render(
        <GridContainer gap="none">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('gap-0');
    });

    it('renders small gap', () => {
      const { container } = render(
        <GridContainer gap="sm">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('gap-2');
    });

    it('renders large gap', () => {
      const { container } = render(
        <GridContainer gap="lg">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('gap-6');
    });

    it('renders horizontal gap', () => {
      const { container } = render(
        <GridContainer gapX="md">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('gap-x-4');
    });

    it('renders vertical gap', () => {
      const { container } = render(
        <GridContainer gapY="lg">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('gap-y-6');
    });
  });

  describe('flow', () => {
    it('has row flow by default', () => {
      const { container } = render(
        <GridContainer>Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-flow-row');
    });

    it('renders column flow', () => {
      const { container } = render(
        <GridContainer flow="col">Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-flow-col');
    });
  });

  describe('auto-fit and auto-fill', () => {
    it('renders auto-fit grid', () => {
      const { container } = render(
        <GridContainer autoFit>Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-[repeat(auto-fit,minmax(250px,1fr))]');
    });

    it('renders auto-fill grid', () => {
      const { container } = render(
        <GridContainer autoFill>Content</GridContainer>
      );

      expect(container.firstChild).toHaveClass('grid-cols-[repeat(auto-fill,minmax(250px,1fr))]');
    });
  });
});

describe('Convenience Components', () => {
  describe('GridCols2', () => {
    it('renders 2 column grid', () => {
      const { container } = render(
        <GridCols2>Content</GridCols2>
      );

      expect(container.firstChild).toHaveClass('grid-cols-2');
    });
  });

  describe('GridCols3', () => {
    it('renders 3 column grid', () => {
      const { container } = render(
        <GridCols3>Content</GridCols3>
      );

      expect(container.firstChild).toHaveClass('grid-cols-3');
    });
  });

  describe('GridCols4', () => {
    it('renders 4 column grid', () => {
      const { container } = render(
        <GridCols4>Content</GridCols4>
      );

      expect(container.firstChild).toHaveClass('grid-cols-4');
    });
  });

  describe('GridAutoFit', () => {
    it('renders auto-fit grid', () => {
      const { container } = render(
        <GridAutoFit>Content</GridAutoFit>
      );

      expect(container.firstChild).toHaveClass('grid-cols-[repeat(auto-fit,minmax(250px,1fr))]');
    });
  });
});
