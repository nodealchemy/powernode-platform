# Frontend Dead Exports Audit — 2026-06-01

> **ARCHIVED 2026-06-03** — Preserved for historical context. See [current docs](../README.md) for current state.

Tech-debt scan output. **Candidates, not confirmed deletions** — verify each before removing.

## Method
- `ts-prune` over `frontend/` → 2,500 unused exports
- Excluded barrel re-exports (`index.ts`/`.tsx`) → 570
- Excluded `default` exports + intra-module-used; grep-verified **0 external references** across `src/` + `e2e/` → **211**

## Caveats
- Conservative: common-named or dynamically-referenced symbols may slip through; some may be intentionally-public API.
- Type exports verified by word-match (annotation usage counts as a reference).
- `debride` (Ruby) tracked separately.

## Dead exports by file (211 total)

### `src/features/ai/audit/api/intelligenceApi.ts` (26)
- useSupplyChainAnalysis
- useRiskSummary
- useVulnerabilityReport
- useAnalyzePipelineFailure
- usePipelineHealth
- useFailureTrends
- useRevenueForecast
- useChurnRisks
- useHealthScores
- useUsageAnomalies
- useTenantChurn
- usePricingRecommendations
- useApiFraud
- usePerformanceScores
- useCommissionOptimization
- useReferralChurnRisks
- useSentimentAnalysis
- useSpamDetection
- useGenerateResponse
- useAgentQuality
- useSmartRouting
- useFatigueAnalysis
- useDigestRecommendations
- usePredictiveFailure
- useSelfHealing
- useSlaBreach

### `src/shared/utils/permissionUtils.ts` (13)
- getUserPermissions
- canCreateKnowledgeBase
- canModerateKnowledgeBase
- hasAdvancedAnalyticsAccess
- getUserRolesInfo
- hasResourceAccess
- canAccessSystemAdmin
- canManageContent
- canManageInfrastructure
- canExportAnalytics
- canAccessAuditLogs
- getResourcePermissionLevel
- hasPermissionConstant

### `src/shared/utils/nodeColorUtils.ts` (13)
- getHttpMethodColor
- getAiProviderColor
- getAiProviderName
- getDatabaseOperationColor
- getTriggerTypeColor
- getMcpOperationColor
- getConditionBranchColor
- getNotificationChannelColor
- getFileOperationColor
- getValidationResultColor
- getLoopTypeColor
- getContentActionColor
- getSortOrderLabel

### `src/shared/types/ai.ts` (12)
- CreateProviderCredentialRequest
- CreateAiAgentRequest
- CreateConversationRequest
- ProviderTestResult
- BulkTestResult
- ProviderUsageSummary
- ExecutionChannelMessage
- MonitoringChannelMessage
- CredentialsFilters
- AgentsFilters
- ConversationsFilters
- ExecutionsFilters

### `src/shared/utils/formatters.ts` (11)
- formatPercent
- toTitleCase
- formatPhoneNumber
- formatCardDisplay
- formatBankAccountDisplay
- formatSubscriptionPrice
- calculateDiscountedPrice
- calculateYearlyPrice
- calculateAnnualSavings
- formatProration
- getPromotionalDiscountDaysRemaining

### `src/features/supply-chain/testing/mockFactories.ts` (9)
- createMockSbomDetail
- createMockLicense
- createMockAlert
- createMockActivityItem
- createMockApiErrorResponse
- createMockPaginatedResponse
- createMockContainerImageList
- createMockAttestationList
- createMockLicenseViolationList

### `src/shared/services/apiUtils.ts` (6)
- wrapListResponse
- normalizePagination
- isSuccessResponse
- isErrorResponse
- safeApiCall
- buildQueryParams

### `src/shared/utils/userUtils.ts` (4)
- getFirstName
- getLastName
- formatUserName
- hasCompleteName

### `src/shared/utils/statusHelpers.ts` (4)
- getStatusBadgeClasses
- isPositiveStatus
- isNegativeStatus
- requiresAttention

### `src/shared/types/monitoring.ts` (4)
- MonitoringWebSocketMessage
- MonitoringInterval
- ComponentStatus
- MonitoringCallbacks

### `src/shared/types/loading.types.ts` (3)
- AsyncLoadingState
- GlobalLoadingState
- LoadingAction

### `src/shared/services/extensionLoader.ts` (3)
- isExtensionLoaded
- getLoadedExtensions
- getExtensionManifest

### `src/shared/hooks/useFormSubmission.ts` (3)
- useApiFormSubmission
- useMultiStepFormSubmission
- useOptimisticFormSubmission

### `src/features/app/types/search.ts` (3)
- SearchContextType
- DEFAULT_FILTER_PRESETS
- VIEW_MODE_OPTIONS

### `src/test-utils.tsx` (2)
- mockPlans
- waitForLoadingToFinish

### `src/shared/utils/typeGuards.ts` (2)
- getStringProperty
- getNumberProperty

### `src/shared/utils/errorHandling.ts` (2)
- createApiError
- getUserFriendlyError

### `src/shared/types/storage.ts` (2)
- NETWORK_FS_PROVIDERS
- StorageProviderConfig

### `src/shared/types/autonomy.ts` (2)
- AutonomyPolicy
- AutonomyAgentInfo

### `src/shared/hooks/redux.ts` (2)
- useAppDispatch
- useAppSelector

### `src/shared/constants/permissions.ts` (2)
- isValidPermission
- PERMISSION_GROUPS

### `src/shared/components/ui/BreadcrumbAwareTabNavigation.tsx` (2)
- BreadcrumbAwareTabNavigation
- BreadcrumbAwareMobileTabNavigation

### `src/shared/components/layout/PageBreadcrumb.tsx` (2)
- PageBreadcrumb
- breadcrumbConfigs

### `src/shared/components/forms/YamlEditor.tsx` (2)
- useYamlEditor
- YamlEditor

### `src/shared/components/forms/CascadingSelect.tsx` (2)
- useCascadingOptions
- CascadingSelect

### `src/shared/components/D3ForceGraph.tsx` (2)
- useGraphData
- D3ForceGraph

### `src/features/ai/memory/api/memoryApi.ts` (2)
- fetchMemoryEntries
- writeMemory

### `src/features/ai/autonomy/types/autonomy.ts` (2)
- AgentGoalDetail
- AgentObservation

### `src/features/ai/autonomy/api/autonomyApi.ts` (2)
- useBudgetCheck
- useBudgetAlerts

### `src/features/admin/services/servicesApi.ts` (2)
- ConfigValidationResult
- ConnectivityTestResult

### `src/features/admin/services/adminApi.ts` (2)
- UserManagementData
- SecuritySettingsData

### `src/types/devops-pipelines.ts` (1)
- DevopsTriggerEvent

### `src/shared/utils/websocketUtils.ts` (1)
- safeWebSocketSend

### `src/shared/utils/debounce.ts` (1)
- debounceAsync

### `src/shared/types/plugin.ts` (1)
- PluginReview

### `src/shared/services/ai/MonitoringApiService.ts` (1)
- HealthComponentStatus

### `src/shared/services/ai/CircuitBreakerApiService.ts` (1)
- circuitBreakerApi

### `src/shared/hooks/useThemeColors.ts` (1)
- useChartColors

### `src/shared/hooks/useOnlineStatus.ts` (1)
- useIsOnline

### `src/shared/components/ui/Loading.tsx` (1)
- LoadingProps

### `src/shared/components/forms/ExampleForm.tsx` (1)
- ExampleForm

### `src/shared/components/error/AiErrorBoundary.tsx` (1)
- MinimalErrorBoundary

### `src/shared/components/approval-chains/ApprovalChainList.tsx` (1)
- ApprovalChainList

### `src/shared/components/ai/AuthenticationCheck.tsx` (1)
- AuthenticationCheck

### `src/pages/app/TestWebSocket.tsx` (1)
- TestWebSocket

### `src/pages/app/ai/AgentMarketplacePage.tsx` (1)
- AgentMarketplaceContent

### `src/features/system/storage/types.ts` (1)
- BulkAssignDryRunRow

### `src/features/devops/swarm/hooks/useSwarmLogs.ts` (1)
- useSwarmLogs

### `src/features/devops/swarm/hooks/useSwarmHealth.ts` (1)
- useSwarmHealth

### `src/features/devops/swarm/components/SwarmLayout.tsx` (1)
- SwarmLayout

### `src/features/devops/swarm/components/ResourceUsageChart.tsx` (1)
- ResourceUsageChart

### `src/features/devops/swarm/components/ClusterCard.tsx` (1)
- ClusterCard

### `src/features/devops/pipelines/hooks/useDevopsWebSocket.ts` (1)
- disconnectDevopsWebSocket

### `src/features/devops/docker/components/VolumeFormModal.tsx` (1)
- VolumeFormModal

### `src/features/devops/docker/components/ImagePullModal.tsx` (1)
- ImagePullModal

### `src/features/devops/docker/components/ImageCard.tsx` (1)
- ImageCard

### `src/features/devops/docker/components/HostCard.tsx` (1)
- HostCard

### `src/features/devops/docker/components/DockerStatsCards.tsx` (1)
- DockerStatsCards

### `src/features/devops/docker/components/DockerLayout.tsx` (1)
- DockerLayout

### `src/features/devops/docker/components/ContainerStatsView.tsx` (1)
- ContainerStatsView

### `src/features/devops/docker/components/ContainerLogViewer.tsx` (1)
- ContainerLogViewer

### `src/features/devops/docker/components/ContainerCreateModal.tsx` (1)
- ContainerCreateModal

### `src/features/devops/docker/components/ActivityTimeline.tsx` (1)
- ActivityTimeline

### `src/features/delegations/services/delegationApi.ts` (1)
- delegationHelpers

### `src/features/content/pages/components/BacklinksPanel.tsx` (1)
- BacklinksPanel

### `src/features/app/types/marketplace.ts` (1)
- getTypeDescription

### `src/features/ai/sandboxes/api/sandboxApi.ts` (1)
- fetchSandbox

### `src/features/ai/parallel-execution/components/SessionList.tsx` (1)
- SessionList

### `src/features/ai/orchestration/services/aiOrchestrationMonitor.ts` (1)
- disconnectAIOrchestrationMonitor

### `src/features/ai/orchestration/components/ProviderStatusCards.tsx` (1)
- ProviderStatusCards

### `src/features/ai/orchestration/components/ExecutionFlowVisualization.tsx` (1)
- ExecutionFlowVisualization

### `src/features/ai/code-review/components/ReviewSummaryPanel.tsx` (1)
- ReviewSummaryPanel

### `src/features/ai/chat/components/TeamActivityMessage.tsx` (1)
- TeamActivityMessage

### `src/features/ai/chat/components/NewConversationTab.tsx` (1)
- NewConversationTab

### `src/features/ai/chat/components/MessageActions.tsx` (1)
- MessageActions

### `src/features/ai/chat/components/FileDropZone.tsx` (1)
- FileDropZone

### `src/features/ai/chat/components/ConversationProfileEditor.tsx` (1)
- ConversationProfileEditor

### `src/features/ai/chat/components/ChatInput.tsx` (1)
- ChatInput

### `src/features/ai/agent-teams/components/TrajectoryViewer.tsx` (1)
- TrajectoryViewer

### `src/features/ai/agent-teams/components/TrajectoryList.tsx` (1)
- TrajectoryList

### `src/features/ai/agent-teams/components/ReviewPanel.tsx` (1)
- ReviewPanel

### `src/features/ai/agent-teams/components/InfrastructureBinding.tsx` (1)
- InfrastructureBinding

### `src/features/ai/agent-teams/components/DevOpsTeamTemplates.tsx` (1)
- DevOpsTeamTemplates

### `src/features/ai/agent-teams/components/CostProfiler.tsx` (1)
- CostProfiler

### `src/features/ai/agent-teams/components/BranchProtectionConfig.tsx` (1)
- BranchProtectionConfig

### `src/features/ai/agent-teams/components/AuthorityConfigSection.tsx` (1)
- AuthorityConfigSection

### `src/features/ai/agents/components/tabs/AgentsListTab.tsx` (1)
- AgentsListTab

### `src/features/admin/workers/components/WorkerDetails.tsx` (1)
- WorkerDetails

### `src/features/admin/workers/components/ServiceList.tsx` (1)
- ServiceList

### `src/features/admin/workers/components/ServiceDetails.tsx` (1)
- ServiceDetails

### `src/features/admin/storage/services/storageApi.ts` (1)
- StorageApiResponse

### `src/features/admin/components/settings/ServicesConfiguration.tsx` (1)
- ServicesConfiguration

### `src/features/admin/components/PlanFeaturesManager.tsx` (1)
- PlanFeaturesManager

### `src/features/admin/audit-logs/services/auditLogsApi.ts` (1)
- AuditLogsPagination


---

# Ruby (server) — debride --rails  [LOW CONFIDENCE]

`debride --rails app/` flagged **3,677** candidate methods. This is heuristic and noisy:
Ruby dynamic dispatch (`send`, `method_missing`, symbol callbacks, MCP action registries) means
many flagged methods ARE called indirectly. Spot-verification: ~1/3 survive a grep check, but even
those can be false (e.g. `send("notify_#{status}")`). **Treat as leads, verify each individually.**

## Top files by candidate count (debride raw)
```
     47 app/models/account.rb
     40 app/models/file_management/object.rb
     23 app/models/user.rb
     23 app/models/supply_chain/vendor.rb
     22 app/models/supply_chain/vendor_monitoring_event.rb
     22 app/models/supply_chain/sbom_vulnerability.rb
     22 app/models/supply_chain/report.rb
     22 app/models/supply_chain/container_image.rb
     22 app/models/review/moderation_action.rb
     21 app/services/worker_job_service.rb
     21 app/models/file_management/storage.rb
     20 app/models/devops/git_repository.rb
     20 app/models/ai/team_message.rb
     20 app/models/ai/conversation.rb
     20 app/controllers/api/v1/ai/skill_graph_controller.rb
     19 app/models/supply_chain/license_violation.rb
     19 app/models/devops/pipeline_template.rb
     19 app/controllers/api/v1/ai/monitoring_controller.rb
     18 app/models/supply_chain/sbom_component.rb
     18 app/models/supply_chain/license_policy.rb
     18 app/models/supply_chain/license_detection.rb
     18 app/models/supply_chain/attestation.rb
     18 app/models/review/notification_delivery.rb
     18 app/models/audit_log.rb
     17 app/services/devops/git/github_api_client.rb
```

_Full raw output: 3,677 methods (not committed; regenerate via `bundle exec debride --rails app/`)._
