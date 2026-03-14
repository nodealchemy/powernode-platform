import * as exports from '../index';

describe('hooks barrel exports', () => {
  describe('useContainerImages exports', () => {
    it('exports useContainerImages', () => {
      expect(exports.useContainerImages).toBeDefined();
      expect(typeof exports.useContainerImages).toBe('function');
    });

    it('exports useContainerImage', () => {
      expect(exports.useContainerImage).toBeDefined();
      expect(typeof exports.useContainerImage).toBe('function');
    });

    it('exports useContainerVulnerabilities', () => {
      expect(exports.useContainerVulnerabilities).toBeDefined();
      expect(typeof exports.useContainerVulnerabilities).toBe('function');
    });

    it('exports useContainerSbom', () => {
      expect(exports.useContainerSbom).toBeDefined();
      expect(typeof exports.useContainerSbom).toBe('function');
    });

    it('exports useEvaluatePolicies', () => {
      expect(exports.useEvaluatePolicies).toBeDefined();
      expect(typeof exports.useEvaluatePolicies).toBe('function');
    });
  });

  describe('useAttestations exports', () => {
    it('exports useAttestations', () => {
      expect(exports.useAttestations).toBeDefined();
      expect(typeof exports.useAttestations).toBe('function');
    });

    it('exports useAttestation', () => {
      expect(exports.useAttestation).toBeDefined();
      expect(typeof exports.useAttestation).toBe('function');
    });

    it('exports useSignAttestation', () => {
      expect(exports.useSignAttestation).toBeDefined();
      expect(typeof exports.useSignAttestation).toBe('function');
    });

    it('exports useSigningKeys', () => {
      expect(exports.useSigningKeys).toBeDefined();
      expect(typeof exports.useSigningKeys).toBe('function');
    });

    it('exports useCreateAttestation', () => {
      expect(exports.useCreateAttestation).toBeDefined();
      expect(typeof exports.useCreateAttestation).toBe('function');
    });
  });
});
