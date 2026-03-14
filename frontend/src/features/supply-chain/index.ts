/**
 * Supply Chain Management Feature
 *
 * Barrel export for all supply chain components, hooks, services, and types
 */

// Types
export * from './types';

// Services
export { supplyChainApi } from './services/supplyChainApi';
export { sbomsApi } from './services/sbomsApi';
export { containerImagesApi } from './services/containerImagesApi';
export { attestationsApi } from './services/attestationsApi';
export { vendorRiskApi } from './services/vendorRiskApi';
export { licenseComplianceApi } from './services/licenseComplianceApi';

// Hooks
export { useSupplyChainDashboard } from './hooks/useSupplyChainDashboard';
export { useSboms, useSbom } from './hooks/useSboms';
export { useContainerImages, useContainerImage } from './hooks/useContainerImages';
export { useAttestations, useAttestation } from './hooks/useAttestations';
export { useVendors, useVendor, useVendorRiskDashboard } from './hooks/useVendorRisk';
export {
  useLicensePolicies,
  useLicensePolicy,
  useCreateLicensePolicy,
  useUpdateLicensePolicy,
  useDeleteLicensePolicy,
  useToggleLicensePolicyActive,
  useLicenseViolations,
  useLicenseViolation,
  useResolveViolation,
  useGrantViolationException,
} from './hooks/useLicenseCompliance';

// Shared Components
export * from './components/shared';

// Pages
export {
  SupplyChainDashboardPage,
  SbomsPage,
  SbomDetailPage,
  ContainerImagesPage,
  ContainerImageDetailPage,
  AttestationsPage,
  AttestationDetailPage,
  VendorsPage,
  VendorDetailPage,
  VendorRiskDashboardPage,
  LicensePoliciesPage,
  LicenseViolationsPage,
} from './pages';
