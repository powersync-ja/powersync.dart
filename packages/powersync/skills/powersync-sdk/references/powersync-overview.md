---
name: powersync-overview
description: PowerSync architecture overview — components, data flow, and links to detailed architecture documentation
metadata:
  tags: architecture, overview, replication, powersync-service, client-sdk
---

# PowerSync Architecture Overview

> **Load this when** you need to understand how PowerSync's components fit together before diving into implementation.

Guidance for understanding all the moving components of PowerSync. For information about the vision of PowerSync, see [PowerSync Philosophy](https://docs.powersync.com/intro/powersync-philosophy.md)

## Architecture

```mermaid
flowchart LR

  %% ── YOUR BACKEND ──────────────────────────────────────
  subgraph BACKEND["Your Backend"]
    direction TB
    DB["Backend Database\n(Postgres | MongoDB | MySQL | Supabase | …)"]
    API["Backend API\n(Your server / cloud functions)"]
    API -- "Applies writes" --> DB
  end

  %% ── POWERSYNC SERVICE (cloud / self-hosted) ──────────
  subgraph PS_SERVICE["PowerSync Service"]
    direction TB
    SYNC["Partial Sync\n(sync rules filter data per user)"]
  end

  %% ── YOUR APP (client) ────────────────────────────────
  subgraph APP["Your App"]
    direction TB
    SDK["PowerSync SDK"]
    SQLITE["In-app SQLite\n(local replica — reads are instant)"]
    QUEUE["Upload Queue\n(offline write buffer)"]
    UI["UI"]
    SDK --- SQLITE
    SDK --- QUEUE
    SQLITE <--> UI
    QUEUE <--> UI
  end

  %% ── DATA FLOW ────────────────────────────────────────
  DB -- "Replicates changes\n(CDC / logical replication)" --> PS_SERVICE
  PS_SERVICE -- "Streams changes\n(real-time sync)" --> SDK
  QUEUE -- "Uploads writes\n(when connectivity resumes)" --> API
```

See [Architecture Overview](https://docs.powersync.com/architecture/architecture-overview.md) for more details on the overall architecture

The list below lists each component, what it is and where to find detailed information about each of them.

| Component            | Description                                                                                                             | Reference                                                                                                         |
|----------------------|-------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| PowerSync Service| The server-side component of the sync engine responsible for the read path from the source database to client-side SQLite databases. | [PowerSync Service](https://docs.powersync.com/architecture/powersync-service.md)                                 |
| PowerSync Client | The PowerSync Client SDK embedded into an application.                                                                  | [Client Architecture](https://docs.powersync.com/architecture/client-architecture.md)                             |
| Protocol         | The Protocol used between PowerSync client applications and the PowerSync Service.                                      | [Protocol](https://docs.powersync.com/architecture/powersync-protocol.md)                                                                                                               |
| Consistency      | The checkpoint based system that ensures data is consistent.                                                            | [Consistency](https://docs.powersync.com/architecture/consistency.md)                                                |