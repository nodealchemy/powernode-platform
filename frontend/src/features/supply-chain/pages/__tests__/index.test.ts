import * as pages from '../index';

describe('pages barrel exports', () => {
  it('exports SupplyChainDashboardPage', () => {
    expect(pages.SupplyChainDashboardPage).toBeDefined();
    expect(typeof pages.SupplyChainDashboardPage).toBe('function');
  });

  it('exports SbomsPage', () => {
    expect(pages.SbomsPage).toBeDefined();
    expect(typeof pages.SbomsPage).toBe('function');
  });

  it('exports SbomDetailPage', () => {
    expect(pages.SbomDetailPage).toBeDefined();
    expect(typeof pages.SbomDetailPage).toBe('function');
  });

  it('exports SbomDiffPage', () => {
    expect(pages.SbomDiffPage).toBeDefined();
    expect(typeof pages.SbomDiffPage).toBe('function');
  });

  it('exports ContainerImagesPage', () => {
    expect(pages.ContainerImagesPage).toBeDefined();
    expect(typeof pages.ContainerImagesPage).toBe('function');
  });

  it('exports ContainerImageDetailPage', () => {
    expect(pages.ContainerImageDetailPage).toBeDefined();
    expect(typeof pages.ContainerImageDetailPage).toBe('function');
  });

  it('exports AttestationsPage', () => {
    expect(pages.AttestationsPage).toBeDefined();
    expect(typeof pages.AttestationsPage).toBe('function');
  });

  it('exports AttestationDetailPage', () => {
    expect(pages.AttestationDetailPage).toBeDefined();
    expect(typeof pages.AttestationDetailPage).toBe('function');
  });

  it('exports VendorsPage', () => {
    expect(pages.VendorsPage).toBeDefined();
    expect(typeof pages.VendorsPage).toBe('function');
  });

  it('exports VendorDetailPage', () => {
    expect(pages.VendorDetailPage).toBeDefined();
    expect(typeof pages.VendorDetailPage).toBe('function');
  });

  it('exports VendorRiskDashboardPage', () => {
    expect(pages.VendorRiskDashboardPage).toBeDefined();
    expect(typeof pages.VendorRiskDashboardPage).toBe('function');
  });

  it('exports AssessmentDetailPage', () => {
    expect(pages.AssessmentDetailPage).toBeDefined();
    expect(typeof pages.AssessmentDetailPage).toBe('function');
  });

  it('exports QuestionnaireDetailPage', () => {
    expect(pages.QuestionnaireDetailPage).toBeDefined();
    expect(typeof pages.QuestionnaireDetailPage).toBe('function');
  });

  it('exports LicensePoliciesPage', () => {
    expect(pages.LicensePoliciesPage).toBeDefined();
    expect(typeof pages.LicensePoliciesPage).toBe('function');
  });

  it('exports LicensePolicyFormPage', () => {
    expect(pages.LicensePolicyFormPage).toBeDefined();
    expect(typeof pages.LicensePolicyFormPage).toBe('function');
  });

  it('exports LicensePolicyDetailPage', () => {
    expect(pages.LicensePolicyDetailPage).toBeDefined();
    expect(typeof pages.LicensePolicyDetailPage).toBe('function');
  });

  it('exports LicenseViolationsPage', () => {
    expect(pages.LicenseViolationsPage).toBeDefined();
    expect(typeof pages.LicenseViolationsPage).toBe('function');
  });

  it('exports LicenseViolationDetailPage', () => {
    expect(pages.LicenseViolationDetailPage).toBeDefined();
    expect(typeof pages.LicenseViolationDetailPage).toBe('function');
  });
});
