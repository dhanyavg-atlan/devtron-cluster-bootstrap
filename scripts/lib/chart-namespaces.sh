#!/bin/sh
# Single source of truth for where each bootstrap chart goes.
# Each chart installs into its OWN namespace (a chart group is NOT bound to one
# environment/namespace — installs are per-chart).
#
# external-secrets MUST land in `external-secrets` — the control-plane TF WIF
# binding targets KSA external-secrets/external-secrets; wrong ns = ESO can't
# authenticate to GCP Secret Manager.

# chart -> Kubernetes namespace it installs into. Default: namespace = chart name.
chart_namespace() {
  case "$1" in
    flux2)             echo "flux-system" ;;
    external-secrets)  echo "external-secrets" ;;
    *)                 echo "$1" ;;
  esac
}

# chart -> SHORT alias used in the Devtron environment name.
# Devtron caps `environment_name` at 16 chars, so we can't use the full namespace;
# the env name is `<cluster>-<alias>` (e.g. poc3-flux, poc3-eso).
chart_env_alias() {
  case "$1" in
    flux2)             echo "flux" ;;
    external-secrets)  echo "eso" ;;
    *)                 echo "$1" ;;
  esac
}
