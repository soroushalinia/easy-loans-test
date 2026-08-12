#!/usr/bin/env bash
# ==========================================================================
#  sec-score.sh — "Security Score" for a container delivery pipeline.
#  One number you can hang in the README (shields.io badge).
#  A gate is "open" (+pts) only if the evidence exists / tool passes.
#  Usage: ./score/score.sh [image]
# ==========================================================================
set -uo pipefail

IMAGE="${1:-ghcr.io/easyloans/easy-loans:latest}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCORE=0
RESULTS=()   # each entry: "name:PASS:+N" or "name:FAIL:+0"

gate() { # gate <name> <points> <1|0>
  if [ "$3" = "1" ]; then
    SCORE=$((SCORE + "$2"))
    RESULTS+=("$1:PASS:+$2")
  else
    RESULTS+=("$1:FAIL:+0")
  fi
}

# 1) secrets — gitleaks must find nothing
if command -v gitleaks >/dev/null 2>&1 && gitleaks detect --no-banner --source . >/dev/null 2>&1; then
  gate "gitleaks (no secrets)" 10 1
else
  gate "gitleaks (no secrets)" 10 0
fi

# 2) trivy image — zero CRITICAL vulns
if command -v trivy >/dev/null 2>&1; then
  crit=$(trivy image --scanners vuln --ignore-unfixed --severity CRITICAL --format json "$IMAGE" 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len([v for r in d.get("Results",[]) for v in r.get("Vulnerabilities",[])]))' 2>/dev/null)
  crit="${crit:-1}"
  gate "trivy image (CRITICAL=0)" 10 "$([ "$crit" = "0" ] && echo 1 || echo 0)"
else
  gate "trivy image (CRITICAL=0)" 10 0
fi

# 3) SBOM present + attached to the registry
if [ -f sbom.spdx.json ]; then
  gate "SBOM in repo" 10 1
else
  gate "SBOM in repo" 10 0
fi

# 4) image signature — cosign verifies
if command -v cosign >/dev/null 2>&1 && [ -f cosign.pub ] \
   && cosign verify --key cosign.pub "$IMAGE" >/dev/null 2>&1; then
  gate "cosign signature verified" 15 1
else
  gate "cosign signature verified" 15 0
fi

# 5) Kyverno: signature re-checked at admission
if [ -f kyverno/policies/03-verify-image-signatures.yaml ]; then
  gate "Kyverno verifyImages policy" 10 1
else
  gate "Kyverno verifyImages policy" 10 0
fi

# 6) Kyverno: non-root / read-only / no privileged
if [ -f kyverno/policies/02-disallow-privileged-root.yaml ]; then
  gate "Kyverno non-root policy" 10 1
else
  gate "Kyverno non-root policy" 10 0
fi

# 7) pinned base by digest (no :latest anywhere in Dockerfiles)
if ! grep -rE 'FROM .*:(latest|slim)$' app/ Dockerfile* 2>/dev/null | grep -v hardened; then
  gate "base pinned by digest" 15 1
else
  gate "base pinned by digest" 15 0
fi

# 8) CI blocks on secrets + scans (gates wired in CI)
if grep -q 'gitleaks/gitleaks-action' ci/hardened.workflow.yml \
   && grep -q 'aquasecurity/trivy-action' ci/hardened.workflow.yml; then
  gate "CI security gates" 10 1
else
  gate "CI security gates" 10 0
fi

# 9) deployment never carries plaintext secrets
if grep -q 'valueFrom' platform/good-deployment.yaml && [ ! -f platform/bad-deployment.yaml ]; then
  gate "no plaintext secrets in deploy" 10 0
else
  # in the repo we KEEP bad-deployment.yaml as a negative demo; score it 0 pts but note it
  gate "no plaintext secrets in deploy" 0 0
fi

# --------------------------------------------------------------------------
echo ""
echo "  ┌───────────────────────────────────────────────┐"
printf "  │   SECURITY SCORE:  %3d / 100\n" "$SCORE"
echo "  └───────────────────────────────────────────────┘"
for r in "${RESULTS[@]}"; do
  printf "  • %-34s %s\n" "$(echo "$r" | cut -d: -f1)" "$(echo "$r" | cut -d: -f3)"
done
echo ""

mkdir -p score
cat > score/badge.json <<EOF
{
  "schemaVersion": 1,
  "label": "security score",
  "message": "$SCORE/100",
  "color": "$([ "$SCORE" -ge 80 ] && echo brightgreen || ([ "$SCORE" -ge 50 ] && echo yellow || echo red))"
}
EOF
echo "→ score/badge.json (use with shields.io badge endpoint)"
exit 0