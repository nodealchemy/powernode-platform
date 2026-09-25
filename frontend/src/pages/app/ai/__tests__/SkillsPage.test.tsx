import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import { SkillsPage } from '../SkillsPage';

jest.mock('@/features/ai/skills/SkillsPage', () => ({ SkillsPage: () => <div data-testid="skills-content" /> }));

// fc-43: the page title matches its AI Agents sidebar item.
describe('SkillsPage', () => {
  it('is titled Skills', () => {
    render(<SkillsPage />);

    expect(screen.getByRole('heading', { name: 'Skills' })).toBeInTheDocument();
    expect(screen.getByTestId('skills-content')).toBeInTheDocument();
  });
});
