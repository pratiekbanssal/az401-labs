#!/usr/bin/env bash
# Lab 1 cleanup: deletes the "mcp-lab" project and everything in it.
# Usage: ./cleanup.sh <your-org-name>

set -euo pipefail

ORG_NAME="${1:-}"
if [[ -z "$ORG_NAME" ]]; then
  echo "Usage: $0 <your-azure-devops-org-name>" >&2
  exit 1
fi

ORG_URL="https://dev.azure.com/${ORG_NAME}"
PROJECT="mcp-lab"

ID=$(az devops project show --project "$PROJECT" --organization "$ORG_URL" --query id -o tsv 2>/dev/null || true)
if [[ -z "$ID" ]]; then
  echo "Project '$PROJECT' not found in $ORG_URL. Nothing to delete."
  exit 0
fi

read -r -p "Delete project '$PROJECT' in $ORG_URL? This removes its work items, repo and wiki. [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "Cancelled."; exit 0; }

az devops project delete --id "$ID" --organization "$ORG_URL" --yes --only-show-errors
echo "Deleted. Remove .vscode/mcp.json too if you no longer need the server."
