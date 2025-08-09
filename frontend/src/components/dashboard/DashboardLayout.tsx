import React from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { toggleSidebar } from '../../store/slices/uiSlice';
import { logout } from '../../store/slices/authSlice';
import { Sidebar } from './Sidebar';
import { Header } from './Header';

interface DashboardLayoutProps {
  children: React.ReactNode;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({ children }) => {
  const dispatch = useDispatch<AppDispatch>();
  const { sidebarOpen, sidebarCollapsed } = useSelector((state: RootState) => state.ui);
  const { user } = useSelector((state: RootState) => state.auth);

  const handleLogout = () => {
    dispatch(logout());
  };

  const handleToggleSidebar = () => {
    dispatch(toggleSidebar());
  };

  return (
    <div className="h-screen flex overflow-hidden bg-theme-background-secondary">
      {/* Sidebar */}
      <Sidebar isOpen={sidebarOpen} onToggle={handleToggleSidebar} />

      {/* Main content */}
      <div className={`flex flex-col w-0 flex-1 overflow-hidden transition-all duration-300 ${
        sidebarCollapsed ? 'md:ml-0' : 'md:ml-0'
      }`}>
        <Header 
          user={user} 
          onLogout={handleLogout}
          onToggleSidebar={handleToggleSidebar}
        />
        
        <main className="flex-1 relative overflow-y-auto focus:outline-none bg-theme-background">
          <div className="py-6">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8">
              {children}
            </div>
          </div>
        </main>
      </div>
    </div>
  );
};