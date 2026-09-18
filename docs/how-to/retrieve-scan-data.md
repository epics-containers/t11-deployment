# Retrieve scan results

A scan produces run metadata in Tiled and detector files in the camera IOC.
This example uses a personal deployment and the task ID printed by blueapi
or the smoke test.

## Find the run in Tiled

Tiled is internal, so query it from the blueapi pod. Replace `YOUR-TASK-ID`
below. The query uses the same test service account as the smoke test and
saves the response to a local `run.json`:

```bash
kubectl exec -i t11-blueapi-0 -c blueapi -- python - > run.json <<'PY'
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

task_id = "YOUR-TASK-ID"
credentials = urlencode({
    "grant_type": "client_credentials",
    "client_id": "system-test-blueapi-alice",
    "client_secret": "secret",
}).encode()
token_url = "http://t11-keycloak:8080/realms/master/protocol/openid-connect/token"
with urlopen(Request(token_url, data=credentials), timeout=20) as response:
    token = json.load(response)["access_token"]
query = urlencode({
    "filter[eq][condition][key]": "start.blueapi_task_id",
    "filter[eq][condition][value]": json.dumps(task_id),
})
request = Request(
    "http://t11-tiled:8000/api/v1/search/?" + query,
    headers={"Authorization": "Bearer " + token},
)
with urlopen(request, timeout=20) as response:
    print(json.dumps(json.load(response), indent=2))
PY
```

In `data[0].attributes.metadata`, look for `start.scan_id`,
`stop.exit_status` and `stop.num_events.primary`. A successful five-reading
`count` has exit status `success` and five primary events. An empty `data`
list means no matching run was returned.

## Copy detector files

The current simulation writes HDF5 files under `/tmp` in the detector pod.
List them, then copy the required file using its actual name:

```bash
kubectl exec bl11t-di-cam-01-0 -c bl11t-di-cam-01 -- \
  find /tmp -type f -name '*.h5'
kubectl cp -c bl11t-di-cam-01 \
  bl11t-di-cam-01-0:/tmp/YOUR-FILE.h5 ./YOUR-FILE.h5
```

Run metadata and detector files are separate: a successful Tiled check does
not prove that the image files remain accessible. Copy what you need before
restarting or tearing down the simulation.
