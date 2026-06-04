import type { A2UIMessage } from './sdk/a2uiSdk';

/**
 * Payload shape carried by a ChatCard of kind 'a2ui_surface'.
 *
 * The backend produces and validates the A2UI v0.9 message frames
 * (createSurface / updateComponents / updateDataModel) and stores them as
 * `messages` in the message's content_metadata; the frontend feeds them
 * straight into the A2UI runtime. Kept transport-agnostic on purpose: the same
 * payload arrives over the HTTP concierge response and the live ActionCable
 * broadcast (the latter only since the serializer keystone fix).
 */
export interface A2uiSurfacePayload {
  /** A2UI spec version stamp, e.g. "v0.9". */
  version: string;
  /** The surface id this payload renders (matches the createSurface frame). */
  surface_id: string;
  /** The ordered A2UI message frames. */
  messages: A2UIMessage[];
}
