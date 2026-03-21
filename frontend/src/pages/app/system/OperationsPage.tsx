import React, { useState, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { OperationList, OperationDetailModal } from '@/features/system/components/operations';
import type { SystemOperation } from '@/features/system/types/system.types';

/**
 * OperationsPage - Main page for viewing system operations
 *
 * Features:
 * - List operations with status filtering
 * - View operation details and event timeline
 * - Track operation progress
 * - Permission-based access control
 */
const OperationsPage: React.FC = () => {
  // Modal state
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [selectedOperationId, setSelectedOperationId] = useState<string | null>(null);

  // Handler for viewing an operation
  const handleView = useCallback((operation: SystemOperation) => {
    setSelectedOperationId(operation.id);
    setShowDetailModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Operations' }
  ];

  return (
    <PageContainer
      title="Operations"
      description="Track and monitor system operations and tasks"
      breadcrumbs={breadcrumbs}
    >
      {/* Operation List */}
      <OperationList onView={handleView} />

      {/* Detail Modal */}
      <OperationDetailModal
        operationId={selectedOperationId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedOperationId(null);
        }}
      />
    </PageContainer>
  );
};

export default OperationsPage;
