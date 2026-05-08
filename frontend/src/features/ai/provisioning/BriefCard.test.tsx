import { act, render, screen } from '@testing-library/react';
import { BriefCard } from './BriefCard';
import type { ProjectBrief } from './types';

describe('BriefCard', () => {
  const emptyBrief: ProjectBrief = {};

  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('renders the project brief heading and confidence pill', () => {
    render(<BriefCard brief={emptyBrief} missingFields={['intent', 'use_case', 'scale', 'regions', 'budget_cap_usd_monthly']} />);
    expect(screen.getByTestId('brief-card')).toBeInTheDocument();
    expect(screen.getByText('Project brief')).toBeInTheDocument();
    expect(screen.getByTestId('brief-confidence-pill')).toHaveTextContent('Sketching…');
  });

  it('flips the confidence pill to Ready to plan when no required fields are missing', () => {
    render(
      <BriefCard
        brief={{
          intent: 'host saas',
          use_case: 'multi-tenant',
          scale: { initial: 100, target: 500 },
          regions: ['us-east-1'],
          budget_cap_usd_monthly: 800
        }}
        missingFields={[]}
      />
    );
    expect(screen.getByTestId('brief-confidence-pill')).toHaveTextContent('Ready to plan');
  });

  it('renders placeholders for missing required fields', () => {
    render(
      <BriefCard
        brief={emptyBrief}
        missingFields={['intent', 'use_case', 'scale', 'regions', 'budget_cap_usd_monthly']}
      />
    );
    const intentField = screen.getByTestId('brief-field-intent');
    expect(intentField).toHaveTextContent('Intent');
    expect(intentField).toHaveTextContent('— required');
  });

  it('formats budget cap with currency and per-month suffix', () => {
    render(
      <BriefCard
        brief={{ budget_cap_usd_monthly: 1500 }}
        missingFields={['intent', 'use_case', 'scale', 'regions']}
      />
    );
    expect(screen.getByTestId('brief-field-budget_cap_usd_monthly')).toHaveTextContent('$1,500/mo');
  });

  it('renders scale as initial→target users plus growth profile', () => {
    render(
      <BriefCard
        brief={{ scale: { initial: 50, target: 1000, growth_profile: 'aggressive' } }}
        missingFields={[]}
      />
    );
    expect(screen.getByTestId('brief-field-scale')).toHaveTextContent('50→1,000 users');
    expect(screen.getByTestId('brief-field-scale')).toHaveTextContent('aggressive');
  });

  it('joins region arrays with commas', () => {
    render(
      <BriefCard
        brief={{ regions: ['us-east-1', 'eu-west-1'] }}
        missingFields={[]}
      />
    );
    expect(screen.getByTestId('brief-field-regions')).toHaveTextContent('us-east-1, eu-west-1');
  });

  it('pulses a field with the theme-info ring when its value updates', () => {
    const initial: ProjectBrief = { intent: 'host saas' };
    const { rerender } = render(<BriefCard brief={initial} missingFields={[]} />);

    // Initial render does not pulse — pulse only on changes.
    expect(screen.getByTestId('brief-field-intent').className).not.toMatch(/ring-theme-info/);

    rerender(<BriefCard brief={{ intent: 'host saas', regions: ['us-east-1'] }} missingFields={[]} />);
    expect(screen.getByTestId('brief-field-regions').className).toMatch(/ring-theme-info/);

    act(() => {
      jest.advanceTimersByTime(250);
    });
    expect(screen.getByTestId('brief-field-regions').className).not.toMatch(/ring-theme-info/);
  });

  describe('M3 — Application code section', () => {
    it("renders 'Application code' section when repo_url is set", () => {
      render(
        <BriefCard
          brief={{ repo_url: 'https://github.com/me/my-bot' }}
          missingFields={[]}
        />
      );
      const section = screen.getByTestId('brief-app-code');
      expect(section).toBeInTheDocument();
      expect(section).toHaveTextContent('App code');
      expect(screen.getByTestId('brief-app-code-repo')).toHaveTextContent(
        'https://github.com/me/my-bot'
      );
    });

    it("renders 'Application code' section when only start_command is set", () => {
      render(
        <BriefCard
          brief={{ start_command: 'node index.js' }}
          missingFields={[]}
        />
      );
      expect(screen.getByTestId('brief-app-code')).toBeInTheDocument();
      expect(screen.getByTestId('brief-app-code-start')).toHaveTextContent('node index.js');
    });

    it("hides 'Application code' section when all M3 fields are null", () => {
      render(
        <BriefCard
          brief={{
            intent: 'host saas',
            repo_url: null,
            branch: null,
            start_command: null,
            runtime_hint: null
          }}
          missingFields={[]}
        />
      );
      expect(screen.queryByTestId('brief-app-code')).not.toBeInTheDocument();
    });

    it('renders the branch alongside the repo URL', () => {
      render(
        <BriefCard
          brief={{ repo_url: 'https://github.com/me/my-bot', branch: 'main' }}
          missingFields={[]}
        />
      );
      const repoRow = screen.getByTestId('brief-app-code-repo');
      expect(repoRow).toHaveTextContent('https://github.com/me/my-bot');
      expect(repoRow).toHaveTextContent('branch:');
      expect(repoRow).toHaveTextContent('main');
    });

    it('makes the repo URL clickable when it is a valid HTTPS URL', () => {
      render(
        <BriefCard
          brief={{ repo_url: 'https://github.com/me/my-bot' }}
          missingFields={[]}
        />
      );
      const link = screen.getByRole('link', { name: 'https://github.com/me/my-bot' });
      expect(link).toHaveAttribute('href', 'https://github.com/me/my-bot');
      expect(link).toHaveAttribute('target', '_blank');
      expect(link).toHaveAttribute('rel', expect.stringContaining('noopener'));
    });

    it('renders a non-URL repo value as plain text (not a link)', () => {
      render(
        <BriefCard
          brief={{ repo_url: 'me/my-bot' }}
          missingFields={[]}
        />
      );
      expect(screen.queryByRole('link')).not.toBeInTheDocument();
      expect(screen.getByTestId('brief-app-code-repo')).toHaveTextContent('me/my-bot');
    });

    it('renders runtime_hint as a friendly badge label (Node.js, Python 3, Docker)', () => {
      const { rerender } = render(
        <BriefCard brief={{ runtime_hint: 'node' }} missingFields={[]} />
      );
      expect(screen.getByTestId('brief-app-code-runtime')).toHaveTextContent('Node.js');

      rerender(<BriefCard brief={{ runtime_hint: 'python' }} missingFields={[]} />);
      expect(screen.getByTestId('brief-app-code-runtime')).toHaveTextContent('Python 3');

      rerender(<BriefCard brief={{ runtime_hint: 'docker' }} missingFields={[]} />);
      expect(screen.getByTestId('brief-app-code-runtime')).toHaveTextContent('Docker');
    });

    it('renders the start command in a monospace code element', () => {
      render(
        <BriefCard
          brief={{ start_command: 'bundle exec rails s' }}
          missingFields={[]}
        />
      );
      const startRow = screen.getByTestId('brief-app-code-start');
      const codeEl = startRow.querySelector('code');
      expect(codeEl).not.toBeNull();
      expect(codeEl).toHaveTextContent('bundle exec rails s');
      expect(codeEl?.className).toMatch(/font-mono/);
    });

    it('pulses the section on field update', () => {
      const { rerender } = render(<BriefCard brief={{}} missingFields={[]} />);

      // No section yet — nothing to pulse.
      expect(screen.queryByTestId('brief-app-code')).not.toBeInTheDocument();

      rerender(
        <BriefCard
          brief={{ repo_url: 'https://github.com/me/my-bot' }}
          missingFields={[]}
        />
      );
      expect(screen.getByTestId('brief-app-code').className).toMatch(/ring-theme-info/);

      act(() => {
        jest.advanceTimersByTime(250);
      });
      expect(screen.getByTestId('brief-app-code').className).not.toMatch(/ring-theme-info/);

      // Updating another M3 field re-pulses the section.
      rerender(
        <BriefCard
          brief={{ repo_url: 'https://github.com/me/my-bot', start_command: 'node index.js' }}
          missingFields={[]}
        />
      );
      expect(screen.getByTestId('brief-app-code').className).toMatch(/ring-theme-info/);
    });
  });
});
