import { memo, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { ComponentRenderer, useDispatchAction } from '../../sdk/a2uiSdk';
import type { Action } from '../../sdk/a2uiSdk';

/**
 * Themed A2UI `Button` — reuses the SDK's action dispatch (so the renderer's
 * `onAction` callback fires with the standard ActionPayload) but renders the
 * platform Button primitive. `primary` selects the themed variant.
 */
interface A2uiButtonProps {
  surfaceId: string;
  componentId: string;
  child?: string;
  text?: string;
  primary?: boolean;
  action?: Action;
  weight?: number;
}

export const A2uiButton = memo(function A2uiButton({
  surfaceId,
  componentId,
  child,
  text,
  primary = false,
  action,
  weight,
}: A2uiButtonProps) {
  const dispatch = useDispatchAction();
  const handleClick = useCallback(() => {
    if (action) dispatch(surfaceId, componentId, action);
  }, [dispatch, surfaceId, componentId, action]);

  return (
    <Button
      variant={primary ? 'primary' : 'secondary'}
      size="sm"
      onClick={handleClick}
      style={weight ? { flexGrow: weight } : undefined}
    >
      {child ? <ComponentRenderer surfaceId={surfaceId} componentId={child} /> : (text ?? 'Button')}
    </Button>
  );
});

A2uiButton.displayName = 'A2ui.Button';
