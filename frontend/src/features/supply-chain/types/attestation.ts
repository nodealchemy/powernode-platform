/**
 * Attestation and Provenance Types
 *
 * Types for SLSA provenance, attestations, and signing
 */

/** Type of attestation document */
export type AttestationType = 'slsa_provenance' | 'sbom' | 'vulnerability_scan' | 'custom';

/** SLSA (Supply chain Levels for Software Artifacts) level */
export type SlsaLevel = 1 | 2 | 3 | null;

/** Attestation verification status */
export type VerificationStatus = 'unverified' | 'verified' | 'failed' | 'expired';

/**
 * Attestation
 * Core attestation metadata and verification status
 */
export interface Attestation {
  id: string;
  attestation_id: string;
  attestation_type: AttestationType;
  slsa_level: SlsaLevel;
  subject_name: string;
  subject_digest: string;
  verification_status: VerificationStatus;
  signed: boolean;
  rekor_logged: boolean;
  created_at: string;
  updated_at: string;
}

/**
 * Build Provenance
 * SLSA provenance information about how an artifact was built
 */
export interface BuildProvenance {
  id: string;
  builder_id: string;
  build_type: string;
  invocation: Record<string, unknown>;
  materials: Array<{ uri: string; digest: Record<string, string> }>;
  metadata: Record<string, unknown>;
}

/**
 * Signing Key
 * Cryptographic key used for signing attestations
 */
export interface SigningKey {
  id: string;
  name: string;
  key_type: 'cosign' | 'gpg' | 'sigstore';
  public_key: string;
  is_default: boolean;
  expires_at?: string;
  created_at: string;
}

/**
 * Attestation Detail
 * Extended attestation information with provenance and verification logs
 */
export interface AttestationDetail extends Attestation {
  build_provenance?: BuildProvenance;
  signing_key?: SigningKey;
  verification_logs?: Array<{
    verified_at: string;
    status: VerificationStatus;
    message?: string;
  }>;
}
