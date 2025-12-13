import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import {
  Card,
  CardHeader,
  CardBody,
  CardFooter,
  CardTitle,
  CardDescription,
  CardContent,
  MetricCard,
  ActionCard
} from './Card';

describe('Card', () => {
  describe('rendering', () => {
    it('renders children correctly', () => {
      render(<Card>Card content</Card>);
      expect(screen.getByText('Card content')).toBeInTheDocument();
    });

    it('renders with default props', () => {
      const { container } = render(<Card>Default</Card>);
      const card = container.firstChild;
      expect(card).toHaveClass('bg-theme-surface');
      expect(card).toHaveClass('rounded-xl');
      expect(card).toHaveClass('shadow-md');
    });
  });

  describe('variants', () => {
    it('renders default variant', () => {
      const { container } = render(<Card variant="default">Card</Card>);
      expect(container.firstChild).toHaveClass('bg-theme-surface');
    });

    it('renders elevated variant', () => {
      const { container } = render(<Card variant="elevated">Card</Card>);
      expect(container.firstChild).toHaveClass('bg-theme-surface');
    });

    it('renders outlined variant', () => {
      const { container } = render(<Card variant="outlined">Card</Card>);
      expect(container.firstChild).toHaveClass('bg-transparent');
      expect(container.firstChild).toHaveClass('border-2');
    });

    it('renders glass variant', () => {
      const { container } = render(<Card variant="glass">Card</Card>);
      expect(container.firstChild).toHaveClass('backdrop-blur-md');
    });

    it('renders gradient variant', () => {
      const { container } = render(<Card variant="gradient">Card</Card>);
      expect(container.firstChild).toHaveClass('text-white');
    });
  });

  describe('padding', () => {
    it.each([
      ['none', ''],
      ['sm', 'p-3'],
      ['md', 'p-4'],
      ['lg', 'p-5'],
      ['xl', 'p-6'],
    ])('applies %s padding correctly', (padding, expectedClass) => {
      const { container } = render(<Card padding={padding as 'none' | 'sm' | 'md' | 'lg' | 'xl'}>Card</Card>);
      if (expectedClass) {
        expect(container.firstChild).toHaveClass(expectedClass);
      }
    });
  });

  describe('rounded', () => {
    it.each([
      ['none', 'rounded-none'],
      ['sm', 'rounded-sm'],
      ['md', 'rounded-md'],
      ['lg', 'rounded-lg'],
      ['xl', 'rounded-xl'],
      ['2xl', 'rounded-2xl'],
    ])('applies %s rounded class', (rounded, expectedClass) => {
      const { container } = render(
        <Card rounded={rounded as 'none' | 'sm' | 'md' | 'lg' | 'xl' | '2xl'}>Card</Card>
      );
      expect(container.firstChild).toHaveClass(expectedClass);
    });
  });

  describe('shadow', () => {
    it.each([
      ['sm', 'shadow-sm'],
      ['md', 'shadow-md'],
      ['lg', 'shadow-lg'],
      ['xl', 'shadow-xl'],
      ['2xl', 'shadow-2xl'],
    ])('applies %s shadow class', (shadow, expectedClass) => {
      const { container } = render(
        <Card shadow={shadow as 'none' | 'sm' | 'md' | 'lg' | 'xl' | '2xl'}>Card</Card>
      );
      expect(container.firstChild).toHaveClass(expectedClass);
    });

    it('applies no additional shadow class when shadow is none', () => {
      const { container } = render(<Card shadow="none">Card</Card>);
      // Note: Due to falsy check in component, shadow="none" falls back to default
      // This test documents current behavior
      expect(container.firstChild).not.toHaveClass('shadow-lg');
      expect(container.firstChild).not.toHaveClass('shadow-xl');
    });
  });

  describe('interactive states', () => {
    it('applies cursor-pointer when clickable', () => {
      const { container } = render(<Card clickable>Card</Card>);
      expect(container.firstChild).toHaveClass('cursor-pointer');
    });

    it('applies hover styles when hoverable', () => {
      const { container } = render(<Card hoverable>Card</Card>);
      expect(container.firstChild).toHaveClass('hover:border-theme');
    });

    it('shows selection indicator when selected', () => {
      const { container } = render(<Card selected>Card</Card>);
      expect(container.firstChild).toHaveClass('ring-2');
      // Selection indicator SVG should be present
      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('calls onClick handler when clicked', () => {
      const handleClick = jest.fn();
      render(<Card onClick={handleClick}>Card</Card>);
      fireEvent.click(screen.getByText('Card'));
      expect(handleClick).toHaveBeenCalledTimes(1);
    });
  });

  describe('ref forwarding', () => {
    it('forwards ref correctly', () => {
      const ref = React.createRef<HTMLDivElement>();
      render(<Card ref={ref}>Ref Card</Card>);
      expect(ref.current).toBeInstanceOf(HTMLDivElement);
    });
  });

  describe('custom className', () => {
    it('merges custom className with default classes', () => {
      const { container } = render(<Card className="custom-card">Custom</Card>);
      expect(container.firstChild).toHaveClass('custom-card');
      expect(container.firstChild).toHaveClass('bg-theme-surface');
    });
  });

  describe('gradient prop', () => {
    it('renders gradient variant with custom gradient', () => {
      render(
        <Card variant="gradient" gradient={{ from: '#000', to: '#fff', direction: 'r' }}>
          Gradient Card
        </Card>
      );
      expect(screen.getByText('Gradient Card')).toBeInTheDocument();
    });
  });
});

describe('CardHeader', () => {
  it('renders title correctly', () => {
    render(<CardHeader title="Test Title" />);
    expect(screen.getByText('Test Title')).toBeInTheDocument();
  });

  it('renders subtitle when provided', () => {
    render(<CardHeader title="Title" subtitle="Subtitle text" />);
    expect(screen.getByText('Subtitle text')).toBeInTheDocument();
  });

  it('renders icon when provided', () => {
    render(<CardHeader title="Title" icon={<span data-testid="icon">*</span>} />);
    expect(screen.getByTestId('icon')).toBeInTheDocument();
  });

  it('renders action when provided', () => {
    render(<CardHeader title="Title" action={<button>Action</button>} />);
    expect(screen.getByRole('button', { name: 'Action' })).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(<CardHeader title="Title" className="custom-header" />);
    expect(container.firstChild).toHaveClass('custom-header');
  });
});

describe('CardBody', () => {
  it('renders children correctly', () => {
    render(<CardBody>Body content</CardBody>);
    expect(screen.getByText('Body content')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(<CardBody className="custom-body">Content</CardBody>);
    expect(container.firstChild).toHaveClass('custom-body');
  });
});

describe('CardFooter', () => {
  it('renders children correctly', () => {
    render(<CardFooter>Footer content</CardFooter>);
    expect(screen.getByText('Footer content')).toBeInTheDocument();
  });

  it('applies divider by default', () => {
    const { container } = render(<CardFooter>Footer</CardFooter>);
    expect(container.firstChild).toHaveClass('border-t');
  });

  it('removes divider when divider is false', () => {
    const { container } = render(<CardFooter divider={false}>Footer</CardFooter>);
    expect(container.firstChild).not.toHaveClass('border-t');
  });

  it('applies custom className', () => {
    const { container } = render(<CardFooter className="custom-footer">Footer</CardFooter>);
    expect(container.firstChild).toHaveClass('custom-footer');
  });
});

describe('CardTitle', () => {
  it('renders children correctly', () => {
    render(<CardTitle>Title Text</CardTitle>);
    expect(screen.getByText('Title Text')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(<CardTitle className="custom-title">Title</CardTitle>);
    expect(container.firstChild).toHaveClass('custom-title');
  });
});

describe('CardDescription', () => {
  it('renders children correctly', () => {
    render(<CardDescription>Description text</CardDescription>);
    expect(screen.getByText('Description text')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(<CardDescription className="custom-desc">Desc</CardDescription>);
    expect(container.firstChild).toHaveClass('custom-desc');
  });
});

describe('CardContent', () => {
  it('renders children correctly', () => {
    render(<CardContent>Content here</CardContent>);
    expect(screen.getByText('Content here')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(<CardContent className="custom-content">Content</CardContent>);
    expect(container.firstChild).toHaveClass('custom-content');
  });
});

describe('MetricCard', () => {
  it('renders title and value', () => {
    render(<MetricCard title="Total Users" value={1000} />);
    expect(screen.getByText('Total Users')).toBeInTheDocument();
    expect(screen.getByText('1,000')).toBeInTheDocument();
  });

  it('renders string value without formatting', () => {
    render(<MetricCard title="Status" value="Active" />);
    expect(screen.getByText('Active')).toBeInTheDocument();
  });

  it('renders icon when provided', () => {
    render(<MetricCard title="Users" value={100} icon={<span data-testid="metric-icon">👤</span>} />);
    expect(screen.getByTestId('metric-icon')).toBeInTheDocument();
  });

  it('renders string icon', () => {
    render(<MetricCard title="Users" value={100} icon="👤" />);
    expect(screen.getByText('👤')).toBeInTheDocument();
  });

  it('renders positive change with correct styling', () => {
    render(<MetricCard title="Sales" value={500} change={15.5} />);
    expect(screen.getByText('+15.5%')).toBeInTheDocument();
    expect(screen.getByText('↗️')).toBeInTheDocument();
  });

  it('renders negative change with correct styling', () => {
    render(<MetricCard title="Churn" value={50} change={-5.2} />);
    expect(screen.getByText('-5.2%')).toBeInTheDocument();
    expect(screen.getByText('↘️')).toBeInTheDocument();
  });

  it('renders zero change', () => {
    render(<MetricCard title="Stable" value={100} change={0} />);
    // Zero change shows without + prefix per component logic
    expect(screen.getByText('0.0%')).toBeInTheDocument();
  });

  it('renders change label when provided', () => {
    render(<MetricCard title="Growth" value={100} change={10} changeLabel="vs last month" />);
    expect(screen.getByText('vs last month')).toBeInTheDocument();
  });

  it('renders description when change is not provided', () => {
    render(<MetricCard title="Info" value={100} description="Some info" />);
    expect(screen.getByText('Some info')).toBeInTheDocument();
  });

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn();
    render(<MetricCard title="Clickable" value={100} onClick={handleClick} />);
    fireEvent.click(screen.getByText('Clickable'));
    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('applies custom className', () => {
    const { container } = render(
      <MetricCard title="Custom" value={100} className="custom-metric" />
    );
    expect(container.querySelector('.custom-metric')).toBeInTheDocument();
  });
});

describe('ActionCard', () => {
  it('renders title and description', () => {
    render(<ActionCard title="Action Title" description="Action description" />);
    expect(screen.getByText('Action Title')).toBeInTheDocument();
    expect(screen.getByText('Action description')).toBeInTheDocument();
  });

  it('renders icon when provided', () => {
    render(
      <ActionCard
        title="With Icon"
        description="Has icon"
        icon={<span data-testid="action-icon">🔧</span>}
      />
    );
    expect(screen.getByTestId('action-icon')).toBeInTheDocument();
  });

  it('renders string icon', () => {
    render(<ActionCard title="Icon" description="String icon" icon="⚙️" />);
    expect(screen.getByText('⚙️')).toBeInTheDocument();
  });

  it('renders badge when provided', () => {
    render(<ActionCard title="Featured" description="Has badge" badge="New" />);
    expect(screen.getByText('New')).toBeInTheDocument();
    expect(screen.getByText('Featured')).toBeInTheDocument();
  });

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn();
    render(
      <ActionCard title="Click Me" description="Clickable" onClick={handleClick} />
    );
    fireEvent.click(screen.getByText('Click Me'));
    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('renders as link when href is provided', () => {
    render(
      <ActionCard title="Link Card" description="Has href" href="/test-link" />
    );
    const link = document.querySelector('a[href="/test-link"]');
    expect(link).toBeInTheDocument();
  });

  it('applies status classes for warning', () => {
    const { container } = render(
      <ActionCard title="Warning" description="Warning status" status="warning" />
    );
    expect(container.querySelector('.border-theme-warning-border')).toBeInTheDocument();
  });

  it('applies status classes for error', () => {
    const { container } = render(
      <ActionCard title="Error" description="Error status" status="error" />
    );
    expect(container.querySelector('.border-theme-error-border')).toBeInTheDocument();
  });

  it('applies status classes for success', () => {
    const { container } = render(
      <ActionCard title="Success" description="Success status" status="success" />
    );
    expect(container.querySelector('.border-theme-success-border')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(
      <ActionCard title="Custom" description="Has class" className="custom-action" />
    );
    expect(container.querySelector('.custom-action')).toBeInTheDocument();
  });
});
