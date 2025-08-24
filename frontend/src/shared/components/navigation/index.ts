// Navigation Components Export
export { NavigationItem } from './NavigationItem';
export { NavigationSection } from './NavigationSection';
export { UserMenu } from './UserMenu';
export { Sidebar } from './Sidebar';
export { Header } from './Header';

// Re-export types and context
export type { NavigationItem as NavigationItemType, NavigationSection as NavigationSectionType, NavigationConfig, MenuState } from '@/shared/types/navigation';
export { useNavigation, NavigationProvider } from '@/shared/hooks/NavigationContext';