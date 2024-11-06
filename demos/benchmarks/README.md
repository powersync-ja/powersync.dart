# PowerSync Benchmark app

This is an app to test:
1. Initial sync time. This can be used to get a sync throughput estimate.
2. Incremental sync latency.

Incremental sync latency tests the total latency of the following sequence:

1. Create a row on the client, recording the creation time.
2. Upload to server via NodeJS demo backend.
3. Postgres adds a default value to one column.
4. The row is synced back down, including the new default column.
5. The client detects that the default column is set (using a watched query).
6. The client updates the row, recording the latency.

For initial sync, bulk data is synced without actively being used by the app, just to measure the sync time.

# Setup

To primarily measure the client-side sync overhead, run the PowerSync service on the same local network as the client.

## Postgres

```sql
CREATE TABLE bulk_data (id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), name text, size_bucket text);
CREATE TABLE benchmark_items(id uuid primary key, description text, client_created_at timestamptz not null, client_received_at timestamptz, server_created_at timestamptz not null default now());

INSERT INTO bulk_data (name, size_bucket) SELECT repeat('a', 20), '10k' FROM generate_series(1, 10000);
INSERT INTO bulk_data (name, size_bucket) SELECT repeat('a', 20), '100k' FROM generate_series(1, 100000);
INSERT INTO bulk_data (name, size_bucket) SELECT repeat('a', 20), '1m' FROM generate_series(1, 1000000);
INSERT INTO bulk_data (name, size_bucket) SELECT repeat('a', 20), '10m' FROM generate_series(1, 10000000);
```

For reference, these rows are around 142 bytes each when synced. However, sync performance is more related to the number of rows than the total data size, unless you have much larger rows.

## PowerSync Service

Use these sync rules:

```yaml
bucket_definitions:
  bucket_items:
    data:
      - select * from benchmark_items
  bulk:
    parameters: select request.parameters() ->> 'size_bucket' as size_bucket
    data:
      - select * from bulk_data where size_bucket = bucket.size_bucket
```

## Demo Backend

The backend is not required measuring initial sync, but is required for measuring latency.

Use the backend here: https://github.com/powersync-ja/powersync-nodejs-backend-todolist-demo

It should write to the same Postgres database as configured above.

## Configure the app

Generate a [temporary token](https://docs.powersync.com/installation/authentication-setup/development-tokens#development-tokens), and configure the credentials in `lib/app_config.dart`.

Currently a size bucket must be hardcoded in the config - one of "10k", "100k", "1m" or "10m" (see the Postgres setup above).

# Usage

Run the app with:

```sh
# Desktop / Mobile
flutter run --release
# Chrome, OPFS
flutter run -d chrome --release --web-header "Cross-Origin-Opener-Policy=same-origin" --web-header "Cross-Origin-Embedder-Policy=require-corp"
```

For Android, you can connect to PowerSync running on localhost by using `adb reverse`:

```sh
adb reverse tcp:8080 tcp:8080
adb reverse tcp:6060 tcp:6060
```

Initial sync time is automatically calculated and displayed.

For incremental sync, create individual records or batches of records, and wait for the latency to be updated. Wait for sync to fully complete after each record before creating the next one.

