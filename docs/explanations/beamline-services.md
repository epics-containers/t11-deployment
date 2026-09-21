# How the beamline services fit together

t11 combines simulated EPICS hardware with Bluesky acquisition services.
Each deployment has its own controls, authentication and data services.
The root Argo CD application deploys them from `t11-services`.

Solid arrows show requests or data flow; dotted arrows show authentication
and authorization. Supporting jobs and database pods are omitted.

```{mermaid}
flowchart TB
    subgraph workstation["Your workstation"]
        direction LR
        phoebus["Phoebus"]
        epics["caget / pvget"]
        client["blueapi CLI / web UI"]
    end

    subgraph beamline["Your t11 deployment"]
        subgraph controls["EPICS controls"]
            opis["t11-epics-opis<br/>Screen server"]
            screens[("Shared OPI files")]
            gateway["t11-epics-gateways<br/>CA and PVA"]
            iocs["Simulated IOCs<br/>Camera · motors · test · synoptic"]
        end

        subgraph acquisition["Acquisition and data"]
            proxy["t11-blueapi-oauth2<br/>Authenticated entry point"]
            blueapi["t11-blueapi<br/>Bluesky plan runner"]
            numtracker["t11-numtracker<br/>Scan numbers and paths"]
            tiled["t11-tiled<br/>Run catalogue"]
            rabbit["t11-rabbitmq<br/>Message broker"]
        end

        subgraph identity["Identity and permissions"]
            keycloak["t11-keycloak<br/>Users and tokens"]
            opa["t11-opa<br/>Access decisions"]
        end
    end

    phoebus -->|"Load screens over HTTP"| opis
    opis -->|"Read"| screens
    iocs -->|"Publish screens"| screens
    phoebus -->|"Live PVs"| gateway
    epics -->|"Read PVs"| gateway
    gateway -->|"CA / PVA"| iocs
    client -->|"HTTP / WebSocket"| proxy
    proxy -->|"API requests"| blueapi
    blueapi -->|"Control devices"| gateway
    blueapi -->|"Allocate scan numbers and paths"| numtracker
    blueapi -->|"Write run documents"| tiled
    blueapi -->|"STOMP messaging"| rabbit
    client -.->|"CLI login"| keycloak
    proxy -.->|"Browser login / tokens"| keycloak
    blueapi -.->|"OIDC"| keycloak
    tiled -.->|"OIDC"| keycloak
    tiled -.->|"Authorize access"| opa
    numtracker -.->|"Authorize requests"| opa

    classDef user fill:#f1f5f9,stroke:#64748b,color:#0f172a
    classDef control fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e
    classDef data fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef auth fill:#fef3c7,stroke:#d97706,color:#78350f
    class phoebus,epics,client user
    class opis,screens,gateway,iocs control
    class proxy,blueapi,numtracker,tiled,rabbit data
    class keycloak,opa auth
```

## Controls

| IOC | Role |
| --- | --- |
| `bl11t-di-cam-01` | Simulated detector, exposed to blueapi as `det`. |
| `bl11t-mo-sim-01` | Simulated motors, including blueapi's `stage` axes. |
| `bl11t-ea-test-01` | Test and diagnostic PVs. |
| `bl11t-synoptic` | Overview screens and component-status PVs. |

Phoebus loads screens from `t11-epics-opis`, backed by storage from
`t11-epics-pvcs`. Live PVs travel separately through `t11-epics-gateways`,
as they do for `caget` and blueapi. Every copy uses the same PV names;
the gateway selects which beamline you control.

## Acquisition and data

The CLI and web UI reach blueapi through `t11-blueapi-oauth2`. Blueapi runs
Bluesky plans using dodal devices connected through the EPICS gateway.
Numtracker supplies scan numbers and paths; Tiled records run documents.
Detector files are written separately by the IOC.

RabbitMQ provides blueapi's message broker. CLI clients use `--ws` to follow
execution over WebSocket, because the broker is internal to the cluster.

## Identity and permissions

Keycloak supplies users and tokens. OPA checks permissions for Numtracker
and Tiled using local test data: `alice` has session `cm12345-1`, and `bob`
has `cm12345-2`. This lets t11 exercise authentication and authorization
without the central DLS services.

## Workstation access

Only the gateway has a LoadBalancer address, consuming one floating IP per
test beamline at DLS. CA/PVA and camera streams use it directly.
The OPI server, blueapi proxy and Keycloak use ClusterIP Services;
`scripts/connect.sh` forwards them to localhost while you use the beamline.
`scripts/urls.sh` prints those local URLs and the gateway address.
Numtracker, Tiled, OPA and RabbitMQ remain internal.
