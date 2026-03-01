import React from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { ArrowLeft, User, Facebook, Twitter, Linkedin, Instagram, Youtube } from 'lucide-react';
import { useFooter } from '@/shared/contexts/FooterContext';

interface PublicPageContainerProps {
  children: React.ReactNode;
  title?: string;
  description?: string;
  showBackButton?: boolean;
  backButtonLabel?: string;
  backButtonHref?: string;
  className?: string;
}

export const PublicPageContainer: React.FC<PublicPageContainerProps> = ({
  children,
  title,
  description,
  showBackButton = false,
  backButtonLabel = "Back",
  backButtonHref = "/",
  className = ""
}) => {
  const { isAuthenticated, user } = useSelector((state: RootState) => state.auth);
  const { footerData } = useFooter();

  // Update document title if provided
  React.useEffect(() => {
    if (title) {
      document.title = `${title} | Powernode`;
    }
    
    return () => {
      document.title = "Powernode";
    };
  }, [title]);

  return (
    <div className={`min-h-screen bg-theme-background ${className}`}>
      {/* Modern Header */}
      <header className="sticky top-0 z-50 backdrop-blur-lg bg-theme-background/95 border-b border-theme">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-20">
            <Link to="/" className="flex items-center space-x-3 group">
              <div className="w-11 h-11 bg-theme-info-solid rounded-xl flex items-center justify-center transform group-hover:scale-105 transition-transform duration-200 shadow-lg">
                <span className="text-white font-bold text-xl">P</span>
              </div>
              <h1 className="text-lg font-bold text-theme-primary">
                Powernode
              </h1>
            </Link>
            
            <div className="flex items-center space-x-6">
              {showBackButton && (
                <Link
                  to={backButtonHref}
                  className="inline-flex items-center space-x-2 text-sm font-semibold text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                >
                  <ArrowLeft className="w-4 h-4" />
                  <span>{backButtonLabel}</span>
                </Link>
              )}

              {isAuthenticated && user ? (
                <div className="flex items-center space-x-4">
                  <span className="text-sm text-theme-secondary">
                    Welcome, {user.name}
                  </span>
                  <Link
                    to="/app"
                    className="inline-flex items-center space-x-2 px-4 py-2 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-lg transition-all duration-200 text-sm shadow-lg"
                  >
                    <User className="w-4 h-4" />
                    <span>Dashboard</span>
                  </Link>
                </div>
              ) : (
                <>
                  <Link
                    to="/login"
                    className="text-sm font-semibold text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                  >
                    Sign in
                  </Link>
                  <Link
                    to="/plans"
                    className="inline-flex items-center space-x-2 px-6 py-3 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl"
                  >
                    <span>Get Started</span>
                  </Link>
                </>
              )}
            </div>
          </div>
        </div>
      </header>

      {/* Page Header Section */}
      {(title || description) && (
        <section className="relative overflow-hidden pt-16 pb-12">
          {/* Background Decorations */}
          <div className="absolute inset-0">
            <div className="absolute top-20 left-10 w-72 h-72 bg-theme-info/5 rounded-full blur-3xl"></div>
            <div className="absolute top-10 right-20 w-96 h-96 bg-theme-info/5 rounded-full blur-3xl"></div>
          </div>

          <div className="relative max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
            {title && (
              <h1 className="text-4xl md:text-5xl lg:text-6xl font-extrabold leading-tight mb-6 text-theme-primary">
                {title}
              </h1>
            )}

            {description && (
              <p className="text-xl md:text-2xl text-theme-secondary max-w-3xl mx-auto leading-relaxed">
                {description}
              </p>
            )}
          </div>
        </section>
      )}

      {/* Main Content */}
      <main className="relative">
        {children}
      </main>

      {/* Modern Footer */}
      <footer className="bg-theme-background-secondary text-theme-primary mt-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* Main Footer Content */}
          <div className="py-16 border-b border-theme">
            <div className="grid lg:grid-cols-4 md:grid-cols-2 gap-8">
              {/* Company Info */}
              <div className="lg:col-span-1">
                <div className="flex items-center space-x-3 mb-6">
                  <div className="w-10 h-10 bg-theme-info-solid rounded-xl flex items-center justify-center">
                    <span className="text-white font-bold text-lg">P</span>
                  </div>
                  <div>
                    <h3 className="text-xl font-bold text-theme-primary">
                      {footerData?.site_name || 'Powernode'}
                    </h3>
                    <p className="text-xs text-theme-tertiary font-medium">Subscription Platform</p>
                  </div>
                </div>
                <p className="text-theme-secondary text-sm leading-relaxed mb-6">
                  {footerData?.footer_description || 'Powerful subscription management platform designed to help businesses grow. Trusted by thousands of companies worldwide.'}
                </p>
                
                {/* Social Media Links */}
                {footerData && (footerData.social_facebook || footerData.social_twitter || footerData.social_linkedin || footerData.social_instagram || footerData.social_youtube) && (
                  <div className="flex items-center space-x-4">
                    {footerData.social_facebook && (
                      <a href={footerData.social_facebook} target="_blank" rel="noopener noreferrer" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200">
                        <Facebook className="w-5 h-5" />
                      </a>
                    )}
                    {footerData.social_twitter && (
                      <a href={footerData.social_twitter} target="_blank" rel="noopener noreferrer" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200">
                        <Twitter className="w-5 h-5" />
                      </a>
                    )}
                    {footerData.social_linkedin && (
                      <a href={footerData.social_linkedin} target="_blank" rel="noopener noreferrer" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200">
                        <Linkedin className="w-5 h-5" />
                      </a>
                    )}
                    {footerData.social_instagram && (
                      <a href={footerData.social_instagram} target="_blank" rel="noopener noreferrer" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200">
                        <Instagram className="w-5 h-5" />
                      </a>
                    )}
                    {footerData.social_youtube && (
                      <a href={footerData.social_youtube} target="_blank" rel="noopener noreferrer" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200">
                        <Youtube className="w-5 h-5" />
                      </a>
                    )}
                  </div>
                )}
              </div>

              {/* Product Links */}
              <div>
                <h4 className="text-theme-primary font-semibold mb-6">Product</h4>
                <ul className="space-y-4">
                  <li>
                    <Link to="/plans" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                      Features
                    </Link>
                  </li>
                  <li>
                    <Link to="/plans" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                      Pricing
                    </Link>
                  </li>
                  <li>
                    <span className="text-theme-quaternary text-sm cursor-default" title="Coming Soon">Integrations</span>
                  </li>
                  <li>
                    <span className="text-theme-quaternary text-sm cursor-default" title="Coming Soon">API Documentation</span>
                  </li>
                </ul>
              </div>

              {/* Support Links */}
              <div>
                <h4 className="text-theme-primary font-semibold mb-6">Support</h4>
                <ul className="space-y-4">
                  <li>
                    <Link to="/pages/help" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm" data-testid="footer-help-center">
                      Help Center
                    </Link>
                  </li>
                  <li>
                    <Link to="/pages/contact" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm" data-testid="footer-contact">
                      Contact Us
                    </Link>
                  </li>
                  <li>
                    <Link to="/status" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm" data-testid="footer-status">
                      System Status
                    </Link>
                  </li>
                </ul>
              </div>

              {/* Company Links */}
              <div>
                <h4 className="text-theme-primary font-semibold mb-6">Company</h4>
                <ul className="space-y-4">
                  <li>
                    <Link to="/pages/about" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm" data-testid="footer-about">
                      About Us
                    </Link>
                  </li>
                  <li>
                    <span className="text-theme-quaternary text-sm cursor-default" title="Coming Soon">Careers</span>
                  </li>
                  <li>
                    <span className="text-theme-quaternary text-sm cursor-default" title="Coming Soon">Blog</span>
                  </li>
                </ul>
              </div>
            </div>
          </div>

          {/* Footer Bottom */}
          <div className="py-8">
            <div className="flex flex-col lg:flex-row items-center justify-between gap-6">
              <div className="flex flex-wrap items-center gap-6 text-sm text-theme-tertiary">
                <span>© {footerData?.copyright_year || new Date().getFullYear()} {footerData?.copyright_text || 'Everett C. Haimes III. All rights reserved.'}</span>
                <div className="flex items-center space-x-6">
                  <Link to="/pages/privacy" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200" data-testid="footer-privacy">
                    Privacy Policy
                  </Link>
                  <Link to="/pages/terms" className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200" data-testid="footer-terms">
                    Terms of Service
                  </Link>
                </div>
              </div>
              
              <div className="flex items-center space-x-6">
                <div className="flex items-center space-x-2 bg-theme-surface px-3 py-2 rounded-full">
                  <div className="w-2 h-2 bg-theme-success-solid rounded-full animate-pulse"></div>
                  <span className="text-xs text-theme-secondary font-medium">All systems operational</span>
                </div>
                <div className="flex items-center space-x-2 text-xs text-theme-tertiary">
                  <span className="text-sm">🛡️</span>
                  <span>SOC 2 Compliant</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
};