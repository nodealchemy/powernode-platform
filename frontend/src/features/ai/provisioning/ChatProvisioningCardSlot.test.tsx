import { render, screen } from '@testing-library/react';
import { ChatProvisioningCardSlot } from './ChatProvisioningCardSlot';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { logger } from '@/shared/utils/logger';
import type { ChatCard } from '@/shared/types/ai';

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

// A card kind core does not render itself is served by whichever extension
// registered a component into the 'ai.chat.card.<kind>' slot; unregistered, it
// renders nothing.
const card = (kind: string): ChatCard =>
  ({ kind, payload: { hello: 'world' } } as unknown as ChatCard);

describe('ChatProvisioningCardSlot extension card kinds', () => {
  afterEach(() => featureRegistry.clear());

  it('renders the component an extension registered for the card kind, with the card', () => {
    const ExtCard = ({ card: c }: { card: ChatCard }) => (
      <div data-testid="ext-card">{String((c.payload as { hello: string }).hello)}</div>
    );
    featureRegistry.registerComponentSlots({
      'ai.chat.card.platform_deployment_wizard': ExtCard as never,
    });

    render(<ChatProvisioningCardSlot card={card('platform_deployment_wizard')} />);

    expect(screen.getByTestId('ext-card')).toHaveTextContent('world');
    expect(screen.getByTestId('chat-card-platform_deployment_wizard')).toBeInTheDocument();
  });

  it('renders nothing, and logs nothing, for a card kind nobody registered', () => {
    const logSpies = (['error', 'warn', 'info'] as const).map((level) =>
      jest.spyOn(logger, level).mockImplementation(() => undefined)
    );

    const { container } = render(
      <ChatProvisioningCardSlot card={card('platform_deployment_wizard')} />
    );

    expect(container).toBeEmptyDOMElement();
    logSpies.forEach((spy) => {
      expect(spy).not.toHaveBeenCalled();
      spy.mockRestore();
    });
  });
});
