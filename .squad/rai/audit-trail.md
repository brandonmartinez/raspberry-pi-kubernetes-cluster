# RAI Audit Trail

> Append-only evidence log. Entries are redacted — never contains raw secrets or harmful content.

<!-- Rai appends findings below -->

---

## Review Entry — 2026-06-26T13:27 EDT

**Reviewer:** Rai  
**Requested by:** Brandon Martinez  
**Scope:** Pre-commit privacy/leak review of two documents for public open-source repo  
**Files reviewed:**
- `docs/reviews/2026-06-26-repo-and-apps-review.md` (231 lines)
- `docs/hardware-inventory.md` (104 lines)

### Checks performed

| Check | Result |
|---|---|
| Real secret / credential values | ✅ None found |
| Credential/env-var names tied to historical leaks | ✅ Explicitly withheld; review doc line 33 states names are "intentionally omitted" |
| Commit SHAs pointing at historical leaks | ✅ Explicitly withheld; review doc line 33 states SHAs are "intentionally omitted" |
| Masked secret previews (e.g. `abc***xyz`) | ✅ None found |
| Public IP addresses (non-RFC1918) | ✅ None; `8.8.8.8`, `8.8.4.4`, `1.1.1.1` are well-known public DNS infra, not personal |
| RFC1918 LAN IPs | 🟡 Present throughout (`192.168.52.x` subnet); ACCEPTABLE per homelab repo brief |
| MAC addresses | ✅ None found |
| Device serial numbers | ✅ None found |
| Personal email addresses | ✅ None; `admin@themartinez.cloud` is an operational ACME contact address, not a personal email |
| Physical-address hints | ✅ None found |
| Internal hostnames + identifying info combined | 🟡 Node FQDNs + IPs listed; standard homelab documentation, no location data |
| Terminology (RAI policy) | ✅ No violations; primary/replica convention followed |

### Findings

No 🔴 Critical findings.

**🟡 Advisory notes (no remediation required):**
1. `admin@themartinez.cloud` — review doc line 39 references this as a hardcoded ACME contact value already in the codebase. Document correctly characterises it as "an operational domain address, not a personal email." No change needed.
2. First name "Brandon" used as issue owner in review doc (lines 89, 216, 225). Expected in a personal homelab repo. Not a PII concern.

### Verdict

**🟢 GREEN — Safe to commit.**

Both documents correctly omit the historical credential names, commit SHAs, and masked previews per the redaction rule. No real secrets, public IPs, MAC addresses, serial numbers, personal emails, or physical-address hints found.
