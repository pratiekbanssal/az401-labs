#!/usr/bin/env bash
# Lab 1 setup: creates a small demo project in your Azure DevOps organization
# so the MCP server has real data to work with.
#
# What it creates in project "mcp-lab":
#   - 1 Epic, 2 User Stories, 2 Tasks, 1 Bug (Agile process), assigned to you
#   - a README and an app file in the default repo
#   - a feature branch and an open pull request
#   - a project wiki with one page
#
# Usage:   ./setup.sh <your-org-name>
# Example: ./setup.sh contoso
#
# Needs: Azure CLI (az) with the azure-devops extension, git, and `az login` done
# with the same Microsoft Entra account you use for Azure DevOps.

set -euo pipefail

ORG_NAME="${1:-}"
if [[ -z "$ORG_NAME" ]]; then
  echo "Usage: $0 <your-azure-devops-org-name>" >&2
  exit 1
fi

ORG_URL="https://dev.azure.com/${ORG_NAME}"
PROJECT="mcp-lab"
REPO="$PROJECT"
# Well-known Microsoft Entra resource ID for Azure DevOps
ADO_RESOURCE="499b84ac-1321-427f-aa17-267ca6975798"

echo "==> Checking tools"
command -v az  >/dev/null || { echo "Azure CLI not found. Install it first." >&2; exit 1; }
command -v git >/dev/null || { echo "git not found. Install it first." >&2; exit 1; }
az extension show --name azure-devops >/dev/null 2>&1 || az extension add --name azure-devops --only-show-errors

ME="$(az account show --query user.name -o tsv)"
echo "    Signed in as: $ME"

az devops configure --defaults organization="$ORG_URL" project="$PROJECT"

echo "==> Creating project '$PROJECT' (Agile process)"
if az devops project show --project "$PROJECT" >/dev/null 2>&1; then
  echo "    Project already exists, reusing it"
else
  az devops project create --name "$PROJECT" --process Agile --visibility private --only-show-errors >/dev/null
fi

new_item() { # type, title, extra args...
  local type="$1" title="$2"; shift 2
  az boards work-item create --type "$type" --title "$title" --assigned-to "$ME" \
    --only-show-errors "$@" --query id -o tsv
}

link_parent() { # child, parent
  az boards work-item relation add --id "$1" --relation-type parent --target-id "$2" --only-show-errors >/dev/null
}

echo "==> Creating work items"
EPIC=$(new_item "Epic" "Checkout v2" --description "Rebuild checkout so it is faster and easier to support.")
STORY1=$(new_item "User Story" "As a shopper I can pay with a saved card" \
  --description "Acceptance: saved cards show on the payment step; the CVV is always asked again.")
STORY2=$(new_item "User Story" "As a shopper I see my order total before I pay" \
  --description "Acceptance: subtotal, tax and shipping are shown before the Pay button.")
TASK1=$(new_item "Task" "Add saved-card API endpoint")
TASK2=$(new_item "Task" "Write unit tests for order total")
BUG=$(new_item "Bug" "Order total is wrong when a discount code is used" \
  --fields "Microsoft.VSTS.Common.Priority=1")

link_parent "$STORY1" "$EPIC"
link_parent "$STORY2" "$EPIC"
link_parent "$TASK1"  "$STORY1"
link_parent "$TASK2"  "$STORY2"
link_parent "$BUG"    "$STORY2"
echo "    Epic #$EPIC, Stories #$STORY1 #$STORY2, Tasks #$TASK1 #$TASK2, Bug #$BUG"

echo "==> Pushing code to the '$REPO' repo"
TOKEN="$(az account get-access-token --resource "$ADO_RESOURCE" --query accessToken -o tsv)"
AUTH=(-c "http.extraheader=Authorization: Bearer ${TOKEN}")
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git -C "$WORK" init -q -b main
git -C "$WORK" config user.name  "MCP Lab"
git -C "$WORK" config user.email "$ME"

cat > "$WORK/README.md" <<'EOF'
# Checkout service

A tiny demo service for the Azure DevOps MCP Server lab.
EOF

cat > "$WORK/order_total.py" <<'EOF'
def order_total(subtotal, tax_rate, shipping, discount=0):
    """Return the order total in dollars."""
    # BUG: the discount is applied after tax and shipping
    total = subtotal + subtotal * tax_rate + shipping
    return round(total - discount, 2)
EOF

git -C "$WORK" add .
git -C "$WORK" commit -q -m "Initial checkout service"
REMOTE="${ORG_URL}/${PROJECT}/_git/${REPO}"
git -C "$WORK" "${AUTH[@]}" push -q "$REMOTE" main 2>/dev/null \
  || git -C "$WORK" "${AUTH[@]}" push -q --force "$REMOTE" main

git -C "$WORK" checkout -q -b fix/discount-order
cat > "$WORK/order_total.py" <<'EOF'
def order_total(subtotal, tax_rate, shipping, discount=0):
    """Return the order total in dollars."""
    discounted = max(subtotal - discount, 0)
    total = discounted + discounted * tax_rate + shipping
    return round(total, 2)
EOF
git -C "$WORK" commit -q -am "Apply discount before tax"
git -C "$WORK" "${AUTH[@]}" push -q --force "$REMOTE" fix/discount-order

echo "==> Opening a pull request"
PR=$(az repos pr list --repository "$REPO" --source-branch fix/discount-order --status active --query "[0].pullRequestId" -o tsv)
if [[ -z "$PR" ]]; then
  PR=$(az repos pr create --repository "$REPO" --source-branch fix/discount-order --target-branch main \
    --title "Fix order total when a discount is used" \
    --description "Applies the discount before tax and shipping." \
    --only-show-errors --query pullRequestId -o tsv)
fi
echo "    PR #$PR (not linked to Bug #$BUG yet; you will do that with MCP)"

echo "==> Creating the project wiki"
if ! az devops wiki show --wiki "${PROJECT}.wiki" >/dev/null 2>&1; then
  az devops wiki create --name "${PROJECT}.wiki" --type projectwiki --only-show-errors >/dev/null
fi
az devops wiki page create --wiki "${PROJECT}.wiki" --path "/Release checklist" --only-show-errors \
  --content $'# Release checklist\n\n1. All tests green\n2. Bug bar: no open priority 1 bugs\n3. Product owner signs off' >/dev/null 2>&1 \
  || echo "    Wiki page already exists, skipping"

cat <<EOF

Done. Your lab data is ready:
  Project:      ${ORG_URL}/${PROJECT}
  Bug to fix:   #${BUG}
  Pull request: #${PR}

Next: copy config/1-read-only.mcp.json to .vscode/mcp.json, replace YOUR_ORG
with "${ORG_NAME}", and continue with Step 3 of the README.
EOF
