import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { siteSettingsApi, FooterData } from '@/features/settings/services/siteSettingsApi';

interface FooterContextType {
  footerData: FooterData | null;
  loading: boolean;
  error: string | null;
  refreshFooterData: () => Promise<void>;
}

const FooterContext = createContext<FooterContextType | undefined>(undefined);

interface FooterProviderProps {
  children: ReactNode;
}

export const FooterProvider: React.FC<FooterProviderProps> = ({ children }) => {
  const [footerData, setFooterData] = useState<FooterData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadFooterData = async (forceRefresh = false) => {
    try {
      setLoading(true);
      setError(null);
      
      // Check if we have cached data and don't need to force refresh
      if (!forceRefresh && footerData && !loading) {
        setLoading(false);
        return;
      }
      
      const response = await siteSettingsApi.getPublicFooter();
      if (response.success) {
        setFooterData(response.data.footer);
      } else {
        setError('Failed to load footer data');
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to load footer data';
      setError(errorMessage);
      
      // Set fallback data if API fails
      setFooterData({
        site_name: 'Powernode',
        copyright_text: 'All rights reserved.',
        copyright_year: new Date().getFullYear().toString(),
        footer_description: 'Powerful subscription management platform designed to help businesses grow.',
        contact_email: 'hello@powernode.org',
        contact_phone: '',
        company_address: '',
        social_facebook: '',
        social_twitter: '',
        social_linkedin: '',
        social_instagram: '',
        social_youtube: ''
      });
    } finally {
      setLoading(false);
    }
  };

  const refreshFooterData = async () => {
    await loadFooterData(true); // Force refresh when explicitly requested
  };

  useEffect(() => {
    loadFooterData();
  }, []);

  const value: FooterContextType = {
    footerData,
    loading,
    error,
    refreshFooterData
  };

  return (
    <FooterContext.Provider value={value}>
      {children}
    </FooterContext.Provider>
  );
};

export const useFooter = (): FooterContextType => {
  const context = useContext(FooterContext);
  if (context === undefined) {
    throw new Error('useFooter must be used within a FooterProvider');
  }
  return context;
};