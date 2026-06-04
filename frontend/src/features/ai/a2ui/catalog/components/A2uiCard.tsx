import { memo } from 'react';
import { Card } from '@/shared/components/ui/Card';
import { ComponentRenderer } from '../../sdk/a2uiSdk';

/**
 * Themed A2UI `Card` component — renders its single child through the SDK's
 * ComponentRenderer inside the platform Card primitive.
 */
interface A2uiCardProps {
  surfaceId: string;
  child?: string;
  weight?: number;
}

export const A2uiCard = memo(function A2uiCard({ surfaceId, child, weight }: A2uiCardProps) {
  return (
    <Card className="p-4" style={weight ? { flexGrow: weight } : undefined}>
      {child ? <ComponentRenderer surfaceId={surfaceId} componentId={child} /> : null}
    </Card>
  );
});

A2uiCard.displayName = 'A2ui.Card';
