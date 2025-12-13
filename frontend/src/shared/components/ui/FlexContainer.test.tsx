import { render, screen } from '@testing-library/react';
import { FlexContainer, FlexRow, FlexCol, FlexCentered, FlexBetween, FlexItemsCenter } from './FlexContainer';

describe('FlexContainer', () => {
  describe('rendering', () => {
    it('renders children', () => {
      render(
        <FlexContainer>
          <span>Child 1</span>
          <span>Child 2</span>
        </FlexContainer>
      );

      expect(screen.getByText('Child 1')).toBeInTheDocument();
      expect(screen.getByText('Child 2')).toBeInTheDocument();
    });

    it('renders as div by default', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild?.nodeName).toBe('DIV');
    });

    it('renders as custom element', () => {
      const { container } = render(
        <FlexContainer as="nav">Content</FlexContainer>
      );

      expect(container.firstChild?.nodeName).toBe('NAV');
    });

    it('applies custom className', () => {
      const { container } = render(
        <FlexContainer className="custom-class">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('flex display', () => {
    it('has flex class', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex');
    });
  });

  describe('direction', () => {
    it('has row direction by default', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-row');
    });

    it('renders column direction', () => {
      const { container } = render(
        <FlexContainer direction="col">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-col');
    });

    it('renders row-reverse direction', () => {
      const { container } = render(
        <FlexContainer direction="row-reverse">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-row-reverse');
    });

    it('renders col-reverse direction', () => {
      const { container } = render(
        <FlexContainer direction="col-reverse">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-col-reverse');
    });
  });

  describe('alignment', () => {
    it('has center alignment by default', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('items-center');
    });

    it('renders start alignment', () => {
      const { container } = render(
        <FlexContainer align="start">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('items-start');
    });

    it('renders end alignment', () => {
      const { container } = render(
        <FlexContainer align="end">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('items-end');
    });

    it('renders stretch alignment', () => {
      const { container } = render(
        <FlexContainer align="stretch">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('items-stretch');
    });

    it('renders baseline alignment', () => {
      const { container } = render(
        <FlexContainer align="baseline">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('items-baseline');
    });
  });

  describe('justify', () => {
    it('has start justify by default', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('justify-start');
    });

    it('renders center justify', () => {
      const { container } = render(
        <FlexContainer justify="center">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('justify-center');
    });

    it('renders end justify', () => {
      const { container } = render(
        <FlexContainer justify="end">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('justify-end');
    });

    it('renders between justify', () => {
      const { container } = render(
        <FlexContainer justify="between">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('justify-between');
    });

    it('renders around justify', () => {
      const { container } = render(
        <FlexContainer justify="around">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('justify-around');
    });

    it('renders evenly justify', () => {
      const { container } = render(
        <FlexContainer justify="evenly">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('justify-evenly');
    });
  });

  describe('wrap', () => {
    it('has nowrap by default', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-nowrap');
    });

    it('renders wrap', () => {
      const { container } = render(
        <FlexContainer wrap="wrap">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-wrap');
    });

    it('renders wrap-reverse', () => {
      const { container } = render(
        <FlexContainer wrap="wrap-reverse">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('flex-wrap-reverse');
    });
  });

  describe('gap', () => {
    it('has no gap by default', () => {
      const { container } = render(
        <FlexContainer>Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('gap-0');
    });

    it('renders small gap', () => {
      const { container } = render(
        <FlexContainer gap="sm">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('gap-2');
    });

    it('renders medium gap', () => {
      const { container } = render(
        <FlexContainer gap="md">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('gap-4');
    });

    it('renders large gap', () => {
      const { container } = render(
        <FlexContainer gap="lg">Content</FlexContainer>
      );

      expect(container.firstChild).toHaveClass('gap-6');
    });
  });
});

describe('Convenience Components', () => {
  describe('FlexRow', () => {
    it('renders row direction', () => {
      const { container } = render(
        <FlexRow>Content</FlexRow>
      );

      expect(container.firstChild).toHaveClass('flex-row');
    });
  });

  describe('FlexCol', () => {
    it('renders column direction', () => {
      const { container } = render(
        <FlexCol>Content</FlexCol>
      );

      expect(container.firstChild).toHaveClass('flex-col');
    });
  });

  describe('FlexCentered', () => {
    it('renders centered content', () => {
      const { container } = render(
        <FlexCentered>Content</FlexCentered>
      );

      expect(container.firstChild).toHaveClass('items-center', 'justify-center');
    });
  });

  describe('FlexBetween', () => {
    it('renders space-between', () => {
      const { container } = render(
        <FlexBetween>Content</FlexBetween>
      );

      expect(container.firstChild).toHaveClass('justify-between');
    });
  });

  describe('FlexItemsCenter', () => {
    it('renders items center with gap', () => {
      const { container } = render(
        <FlexItemsCenter>Content</FlexItemsCenter>
      );

      expect(container.firstChild).toHaveClass('items-center', 'gap-2');
    });
  });
});
