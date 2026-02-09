// Dashboard Layout with Rebuilt Navigation
import React from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { toggleSidebar } from '@/shared/services/slices/uiSlice';
import { Sidebar, Header } from '../navigation';
import { NavigationProvider } from '@/shared/hooks/NavigationContext';
import { ImpersonationBanner } from '@/features/admin/components/ImpersonationBanner';
import { ChatWindowProvider } from '@/features/ai/chat/context/ChatWindowContext';
import { ChatWindowRoot } from '@/features/ai/chat/components/ChatWindowRoot';
import { FloatingChatWidget } from '@/features/ai/chat/components/FloatingChatWidget';

interface DashboardLayoutProps {
  children: React.ReactNode;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({ children }) => {
  const dispatch = useDispatch<AppDispatch>();
  const { sidebarOpen } = useSelector((state: RootState) => state.ui);

  const handleToggleSidebar = () => {
    dispatch(toggleSidebar());
  };

  return (
    <NavigationProvider>
      <ChatWindowProvider>
        <div className="h-screen flex overflow-hidden bg-theme-background-secondary">
          {/* Sidebar */}
          <Sidebar isOpen={sidebarOpen} onToggle={handleToggleSidebar} />

          {/* Main content */}
          <div className="flex flex-col w-0 flex-1 overflow-hidden">
            <Header onToggleSidebar={handleToggleSidebar} />

            {/* Impersonation Banner */}
            <ImpersonationBanner />

            <main className="flex-1 relative overflow-y-auto focus:outline-none bg-theme-background">
              <div className="py-6">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8">
                  {children}
                </div>
              </div>
            </main>
          </div>

          <FloatingChatWidget />
          <ChatWindowRoot />
        </div>
      </ChatWindowProvider>
    </NavigationProvider>
  );
};

export default DashboardLayout;
