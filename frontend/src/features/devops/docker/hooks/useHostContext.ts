import { useContext } from 'react';
import { HostContext } from '../context/HostContext';

export function useHostContext() {
  return useContext(HostContext);
}
