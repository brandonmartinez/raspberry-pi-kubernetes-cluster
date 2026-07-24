---
updated_at: 2026-07-24T17:39:09-04:00
focus_area: 2026-07-24 DNS resilience remediation deployed and verified
active_issues: []
---

# What We're Focused On

DNS resilience remediation (2026-07-24) is deployed: per-ordinal Pi-hole Services, independent dnsdist health checks, safe readiness, Prometheus rules, validation, and runbooks. Uptime Kuma scraping is removed to conserve memory; standalone Uptime monitoring remains.

## Completed (2026-07-24)

- 🟢 **DNS resilience remediation** — Commit `7a2f500` deployed through observed manual Argo syncs. Fresh Longhorn backups completed for all Pi-hole and monitoring PVCs. Pi-hole, dnsdist, monitoring, and monitoring-config are Synced/Healthy with automated sync off. Final checks passed: VIP 300/300 UDP and TCP; every ordinal 100/100 UDP and TCP plus `version.bind`; zero dnsdist backend-down transitions; five DNS alert rules loaded with none pending/firing. Helm and kubeconform remained unavailable during local validation.
