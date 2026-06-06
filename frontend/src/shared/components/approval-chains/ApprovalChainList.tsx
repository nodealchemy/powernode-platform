import { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { PencilIcon, TrashIcon, PlusIcon } from '@heroicons/react/24/outline';
import { EntityLink } from '@/shared/components/entity';
import { ApprovalChainEditor } from './ApprovalChainEditor';
import { useApprovalChains } from '@/shared/hooks/useApprovalChains';
import type { ApprovalChain } from '@/shared/types/approval';

/**
 * List + manage approval chains for the current account. Used inside the
 * System Settings → Approval Chains tab. Each chain shows step count, usage
 * count, and inline edit/delete buttons.
 */
export function ApprovalChainList() {
  const { chains, loading, create, update, delete: remove, get } = useApprovalChains();
  const [editing, setEditing] = useState<ApprovalChain | null>(null);
  const [showNew, setShowNew] = useState(false);
  const [armedDelete, setArmedDelete] = useState<string | null>(null);

  const handleEdit = async (chain: ApprovalChain) => {
    // Fetch full detail so step bodies are populated.
    const full = await get(chain.id);
    setEditing(full);
  };

  const handleDelete = async (id: string) => {
    if (armedDelete !== id) {
      setArmedDelete(id);
      setTimeout(() => setArmedDelete((cur) => (cur === id ? null : cur)), 5000);
      return;
    }
    await remove(id);
    setArmedDelete(null);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-theme-primary">Approval Chains</h3>
          <p className="text-xs text-theme-tertiary mt-0.5">
            Multi-step workflows assigned to high-risk action policies
          </p>
        </div>
        <Button variant="primary" size="sm" onClick={() => setShowNew(true)}>
          <PlusIcon className="h-4 w-4" /> New Chain
        </Button>
      </div>

      {loading ? (
        <p className="text-sm text-theme-tertiary py-6 text-center">Loading…</p>
      ) : chains.length === 0 ? (
        <div className="text-center py-8 border border-dashed border-theme rounded-lg">
          <p className="text-sm text-theme-tertiary mb-2">No approval chains yet</p>
          <p className="text-xs text-theme-tertiary">
            Create a chain to enforce multi-step approval on high-risk actions
          </p>
        </div>
      ) : (
        <div className="rounded-lg border border-theme overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-theme-background-secondary text-theme-tertiary text-xs">
              <tr>
                <th className="text-left px-3 py-2 font-medium">Name</th>
                <th className="text-left px-3 py-2 font-medium">Steps</th>
                <th className="text-left px-3 py-2 font-medium">Mode</th>
                <th className="text-left px-3 py-2 font-medium">Timeout</th>
                <th className="text-left px-3 py-2 font-medium">Used</th>
                <th className="text-right px-3 py-2 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {chains.map((chain) => (
                <tr key={chain.id} className="border-t border-theme">
                  <td className="px-3 py-2">
                    <EntityLink
                      type="approval_chain"
                      id={chain.id}
                      label={chain.name}
                      className="font-medium text-theme-primary"
                    />
                    {chain.description && (
                      <div className="text-xs text-theme-tertiary">{chain.description}</div>
                    )}
                  </td>
                  <td className="px-3 py-2 text-theme-secondary">{chain.step_count}</td>
                  <td className="px-3 py-2 text-theme-secondary">
                    {chain.is_sequential ? 'Sequential' : 'Parallel'}
                  </td>
                  <td className="px-3 py-2 text-theme-secondary">
                    {chain.timeout_hours ? `${chain.timeout_hours}h → ${chain.timeout_action}` : '—'}
                  </td>
                  <td className="px-3 py-2 text-theme-tertiary">{chain.usage_count || 0}</td>
                  <td className="px-3 py-2 text-right">
                    <div className="flex items-center justify-end gap-1">
                      <button
                        onClick={() => handleEdit(chain)}
                        className="p-1 text-theme-tertiary hover:text-theme-primary rounded"
                        aria-label="Edit chain"
                      >
                        <PencilIcon className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => handleDelete(chain.id)}
                        className={`p-1 rounded ${
                          armedDelete === chain.id
                            ? 'text-theme-danger bg-theme-danger/10'
                            : 'text-theme-tertiary hover:text-theme-danger'
                        }`}
                        aria-label={armedDelete === chain.id ? 'Confirm delete' : 'Delete chain'}
                      >
                        <TrashIcon className="h-4 w-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {(showNew || editing) && (
        <ApprovalChainEditor
          isOpen={showNew || !!editing}
          chain={editing}
          onClose={() => {
            setShowNew(false);
            setEditing(null);
          }}
          onSave={async (payload) => {
            if (editing) await update(editing.id, payload);
            else await create(payload);
          }}
        />
      )}
    </div>
  );
}
