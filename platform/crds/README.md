# Platform CRDs

CRDs for platform charts will be split into dedicated, never-pruned ArgoCD Applications under `platform/crds/<stack>` before prune is enabled on any chart Application.

For the initial live-cluster adoption, CRDs remain chart-delivered (matching the legacy Helm flow). Cluster-wide prune is off, so this is safe for now. Do not add CRD Applications until the live CRD versions have been captured and the adoption runbook gates are complete.
