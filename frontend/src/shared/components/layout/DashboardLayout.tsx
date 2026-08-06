// Dashboard Layout with Rebuilt Navigation
import React from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { toggleSidebar } from '@/shared/services/slices/uiSlice';
import { Sidebar, Header } from '@/shared/components/navigation';
import { NavigationProvider } from '@/shared/hooks/NavigationContext';
import { ImpersonationBanner } from '@/features/admin/components/ImpersonationBanner';
import { SetupPendingBanner } from '@/features/setup/SetupPendingBanner';
import { ChatWindowProvider } from '@/features/ai/chat/context/ChatWindowContext';
import { ChatWindowRoot } from '@/features/ai/chat/components/ChatWindowRoot';
import { FloatingChatWidget } from '@/features/ai/chat/components/FloatingChatWidget';
import { AgentDetailModal } from '@/features/ai/agents/components/AgentDetailModal';
import { TeamDetailModal } from '@/features/ai/agent-teams/components/TeamDetailModal';
import { MissionDetailModal } from '@/features/missions/components/MissionDetailModal';
import { EntityReferenceHost } from '@/shared/components/entity/EntityReferenceHost';
import { KillSwitchStatusBar } from '@/features/ai/autonomy/components/KillSwitchStatusBar';

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
        <div className="h-screen flex flex-col overflow-hidden bg-theme-background-secondary">
          {/* Full-width setup banner — renders null unless extensions have pending
              setup. Lives inside the h-screen column (not above it) so its height
              compresses the sidebar+content row instead of overflowing the viewport
              and clipping the bottom of the sidebar. */}
          <SetupPendingBanner />

          <div className="flex flex-1 min-h-0 overflow-hidden">
            {/* Sidebar */}
            <Sidebar isOpen={sidebarOpen} onToggle={handleToggleSidebar} />

            {/* Main content */}
            <div className="flex flex-col w-0 flex-1 min-w-0">
              <Header />

              {/* Impersonation Banner */}
              <ImpersonationBanner />

              <main className="flex-1 relative overflow-y-auto overflow-x-hidden focus:outline-none bg-theme-background">
                <div className="py-6">
                  <div className="px-4 sm:px-6 md:px-8">
                    {children}
                  </div>
                </div>
              </main>
            </div>
          </div>

          <FloatingChatWidget />
          <ChatWindowRoot />
          <AgentDetailModal />
          <TeamDetailModal />
          <MissionDetailModal />
          <EntityReferenceHost />
          <KillSwitchStatusBar />
        </div>
      </ChatWindowProvider>
    </NavigationProvider>
  );
};

export default DashboardLayout;
