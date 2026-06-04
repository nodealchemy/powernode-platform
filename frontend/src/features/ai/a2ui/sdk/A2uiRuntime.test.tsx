import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { A2uiRuntime } from './A2uiRuntime';
import type { A2UIMessage } from './a2uiSdk';

/**
 * Seam proof for the hybrid A2UI integration: feed a surface from our OWN
 * source (mirrors an ActionCable-delivered card payload), render it through the
 * SDK runtime with our THEMED catalog override, and route a user action back.
 */
const surface: A2UIMessage[] = [
  { createSurface: { surfaceId: 'main', catalogId: 'powernode/a2ui/v0.9/themed' } },
  {
    updateComponents: {
      surfaceId: 'main',
      components: [
        { id: 'root', component: 'Column', children: ['card', 'btn'] },
        { id: 'card', component: 'Card', child: 'greeting' },
        { id: 'greeting', component: 'Text', text: 'Hello from A2UI', variant: 'h3' },
        { id: 'btn', component: 'Button', primary: true, text: 'Submit', action: { name: 'submit' } },
      ],
    },
  },
];

describe('A2uiRuntime (hybrid SDK runtime + themed catalog)', () => {
  it('renders a surface fed from our own transport, themed via the design system', () => {
    render(<A2uiRuntime messages={surface} surfaceId="main" />);

    // Transport-agnostic feed: content from our surface document appears.
    const text = screen.getByText('Hello from A2UI');
    expect(text).toBeInTheDocument();

    // Catalog override: our themed Text wrapper rendered (theme class present) —
    // the SDK's standard Text would NOT emit theme-* classes.
    expect(text).toHaveClass('text-theme-primary');
  });

  it('routes a button action back through onAction with the standard payload', async () => {
    const onAction = jest.fn();
    render(<A2uiRuntime messages={surface} surfaceId="main" onAction={onAction} />);

    await userEvent.click(screen.getByRole('button', { name: 'Submit' }));

    expect(onAction).toHaveBeenCalledTimes(1);
    expect(onAction).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'submit', surfaceId: 'main', sourceComponentId: 'btn' })
    );
  });

  it('renders nothing for an empty surface feed', () => {
    const { container } = render(<A2uiRuntime messages={[]} surfaceId="main" />);
    expect(container).toBeEmptyDOMElement();
  });
});
