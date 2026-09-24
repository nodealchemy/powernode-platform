import { useEffect, useState } from 'react';
import { featureRegistry, type PublicRouteRole } from '@/shared/services/featureRegistry';

/**
 * The path of the public route an extension registered for `role`, or
 * undefined when none did. Re-reads when the registry changes, so a route
 * registered after first render still shows up.
 */
export const usePublicRoutePath = (role: PublicRouteRole): string | undefined => {
  const [path, setPath] = useState(() => featureRegistry.getPublicRoutePath(role));
  useEffect(() => {
    setPath(featureRegistry.getPublicRoutePath(role));
    return featureRegistry.subscribe(() => setPath(featureRegistry.getPublicRoutePath(role)));
  }, [role]);
  return path;
};
