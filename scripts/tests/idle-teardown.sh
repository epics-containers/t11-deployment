#!/bin/bash
# Requires helm dependency build apps before running.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

render() {
    helm template t11 "$root/apps" --namespace t11-beamline "$@"
}

# Default deployments and an explicitly disabled reference stay permanent.
output=$(render)
[[ $output != *'kind: CronJob'* ]]
output=$(render --set testBeamline.enabled=true \
    --set testBeamline.idleTeardown.enabled=false)
[[ $output != *'kind: CronJob'* ]]

# Enabling idle teardown alone must not enable the test profile.
output=$(render --set testBeamline.idleTeardown.enabled=true)
[[ $output != *'kind: CronJob'* ]]

# Test deployments can expire in t11-beamline as well as personal namespaces.
for namespace in t11-beamline personal-test; do
    output=$(render --set destination.namespace="$namespace" \
        --set destination.name=pollux --set testBeamline.enabled=true \
        --set testBeamline.idleTeardown.enabled=true)
    [[ $output == *'kind: CronJob'* ]]
done
echo 'PASS: idle teardown follows the test profile and enabled setting in every namespace'
