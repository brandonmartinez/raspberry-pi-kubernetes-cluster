# Platform CRDs

CRDs for platform charts are split into dedicated, never-pruned ArgoCD Applications under `platform/crds/<stack>` before prune is enabled on any chart Application.

Each CRD bundle must match the live chart version and be synced with `ServerSideApply=true` before syncing the owning chart Application. Update CRD manifests only when upgrading the corresponding chart.
