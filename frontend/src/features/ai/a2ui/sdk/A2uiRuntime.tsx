import { memo } from 'react';
import { A2UIProvider, A2UIRenderer } from './a2uiSdk';
import type { A2UIMessage, ActionHandler, Catalog } from './a2uiSdk';
import { themedCatalog } from '../catalog/themedCatalog';

export interface A2uiRuntimeProps {
  /** The A2UI v0.9 message frames (createSurface / updateComponents / ...). */
  messages: A2UIMessage[];
  /** Fired when the user triggers an action on the surface. */
  onAction?: ActionHandler;
  /** Render a specific surface; renders all if omitted. */
  surfaceId?: string;
  /** Catalog override (defaults to the platform-themed catalog). */
  catalog?: Catalog;
}

/**
 * Swap seam: the ONLY component that mounts the A2UI SDK renderer. Feeds it
 * surface frames obtained from ANY transport (here: an ActionCable-delivered
 * chat card payload) and routes actions back via `onAction`. Swapping the
 * underlying renderer is a change to this file + a2uiSdk.ts only.
 */
export const A2uiRuntime = memo(function A2uiRuntime({
  messages,
  onAction,
  surfaceId,
  catalog = themedCatalog,
}: A2uiRuntimeProps) {
  return (
    <A2UIProvider messages={messages} catalog={catalog}>
      <A2UIRenderer surfaceId={surfaceId} onAction={onAction} />
    </A2UIProvider>
  );
});

A2uiRuntime.displayName = 'A2uiRuntime';
