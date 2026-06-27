# Work Routing

How to decide who handles what.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| GitOps control plane & architecture | Ripley | ArgoCD root/appset/projects, sync waves, promotion gates, app-of-apps structure |
| Kubernetes apps & platform stacks | Dallas | `apps/<app>` Kustomize bases, `platform/<stack>` Helm values, HA (probes/PDB/HPA/spread), Traefik ingress |
| Observability & monitoring | Ash | `platform/monitoring` (Prometheus/Grafana/Alertmanager/exporters), ServiceMonitors/PrometheusRules/dashboards, scrape & retention tuning, Uptime Kuma synthetic checks, sizing of the monitoring stack |
| Node provisioning & Ansible | Parker | Ansible roles, `provision.yml`/`adopt.yml`, k3s server/agent, storage, `bootstrap/` |
| Secrets, TLS & security | Bishop | `secrets/templates` `op://` refs, `sync-secrets.sh`, cert-manager/TLS, `validate.sh` guards |
| Documentation | Lambert | `docs/`, runbooks, `README.md`, keeping docs accurate for open-source learners |
| Code review & approval | Ripley | Review changes, check production safety, enforce promotion gates |
| Validation | (change owner) | `scripts/validate.sh` before commit; Ripley reviews results |
| Scope & priorities | Ripley | What to change next, trade-offs, architectural decisions |
| Session logging | Scribe | Automatic — never needs routing |
| RAI / secret-leak review | Rai | Credential/secret scanning, privacy, content safety, ethical review |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Lead |
| `squad:{name}` | Pick up issue and complete the work | Named member |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, the **Lead** triages it — analyzing content, assigning the right `squad:{member}` label, and commenting with triage notes.
2. When a `squad:{member}` label is applied, that member picks up the issue in their next session.
3. Members can reassign by removing their label and adding another member's label.
4. The `squad` label is the "inbox" — untriaged issues waiting for Lead review.

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work.
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.** Don't spawn an agent for "what port does the server run on?"
4. **When two agents could handle it**, pick the one whose domain is the primary concern.
5. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
6. **Anticipate downstream work.** If a feature is being built, spawn the tester to write test cases from requirements simultaneously.
7. **Issue-labeled work** — when a `squad:{member}` label is applied to an issue, route to that member. The Lead handles all `squad` (base label) triage.
8. **Resource sizing is shared.** Ash owns the monitoring stack's own requests/limits and advises (with measured Prometheus numbers) on endpoint sizing; **Dallas owns the change** to an app/platform manifest. Pair them whenever a sizing change could let either the stack or an endpoint tank.
