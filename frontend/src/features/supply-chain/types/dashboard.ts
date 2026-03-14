/**
 * Supply Chain Dashboard Types
 *
 * Types for dashboard metrics, alerts, and activity
 */

import type { Severity } from './sbom';

/**
 * Alert
 * Security or compliance alert notification
 */
export interface Alert {
  id: string;
  type: 'vulnerability' | 'license' | 'vendor' | 'container' | 'attestation';
  severity: Severity;
  title: string;
  message: string;
  entity_id: string;
  entity_type: string;
  created_at: string;
}

/**
 * Activity Item
 * Recent activity log entry
 */
export interface ActivityItem {
  id: string;
  action: string;
  entity_type: string;
  entity_name: string;
  user_name?: string;
  details?: string;
  created_at: string;
}

/**
 * Supply Chain Dashboard
 * Aggregated metrics and summaries for supply chain security
 */
export interface SupplyChainDashboard {
  sbom_count: number;
  vulnerability_count: number;
  critical_vulnerabilities: number;
  high_vulnerabilities: number;
  container_image_count: number;
  quarantined_images: number;
  verified_images: number;
  attestation_count: number;
  verified_attestations: number;
  vendor_count: number;
  high_risk_vendors: number;
  vendors_needing_assessment: number;
  license_violation_count: number;
  open_violations: number;
  recent_alerts: Alert[];
  recent_activity: ActivityItem[];
}

/**
 * Pagination
 * Pagination metadata for API responses
 */
export interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

/**
 * API Response
 * Generic API response wrapper
 */
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
}

/**
 * Paginated Response
 * API response with pagination
 */
export interface PaginatedResponse<T> {
  success: boolean;
  data?: {
    items: T[];
    pagination: Pagination;
  };
  error?: string;
}
