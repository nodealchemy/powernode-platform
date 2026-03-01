// Navigation Components Export
export { NavigationItem } from '@/shared/components/navigation/NavigationItem';
export { NavigationSection } from '@/shared/components/navigation/NavigationSection';
export { UserMenu } from '@/shared/components/navigation/UserMenu';
export { Sidebar } from '@/shared/components/navigation/Sidebar';
export { Header } from '@/shared/components/navigation/Header';

// Re-export types and context
export type { NavigationItem as NavigationItemType, NavigationSection as NavigationSectionType, NavigationConfig, MenuState } from '@/shared/types/navigation';
export { useNavigation, NavigationProvider } from '@/shared/hooks/NavigationContext';