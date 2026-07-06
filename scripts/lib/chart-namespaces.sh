#!/bin/sh
# Single source of truth: which namespace each bootstrap chart installs into.
# Each chart in the onboarding group goes to ITS OWN namespace (a chart group is
# NOT bound to one environment/namespace — installs are per-chart).
#
# external-secrets MUST land in `external-secrets` — the control-plane TF WIF
# binding targets KSA external-secrets/external-secrets; wrong ns = ESO can't
# authenticate to GCP Secret Manager.
#
# Default: namespace = chart name. Add overrides below as the group grows.
chart_namespace() {
  case "$1" in
    flux2)             echo "flux-system" ;;
    external-secrets)  echo "external-secrets" ;;
    *)                 echo "$1" ;;
  esac
}
