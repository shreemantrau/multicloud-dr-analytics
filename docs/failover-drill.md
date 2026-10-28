# Front Door failover drill (2026-10-26)

Setup: Azure Front Door Standard, origin group with Azure web app (priority 1) and AWS ALB (priority 2).
Health probe: GET /health over HTTP every 5 seconds. Client loop: curl every 2 seconds.

## Failover (Azure stopped)
Azure web app stopped at 16:39:00.

```
16:39:09 Served by: Azure | App tier says: {"db_result
16:39:12 Served by: Azure | App tier says: {"db_result
16:39:15 <!DOCTYPE html><html><head><title>Web App - Unavailable
16:39:17 (empty)
...
16:40:33 <!DOCTYPE html><html><head><title>Web App - Unavailable
16:40:36 Served by: AWS | App tier says: {"db_result
```

Result: first answer from AWS at 16:40:36, about 96 seconds after the stop (first visible error at 16:39:07).

## Failback (Azure started)
Azure web app started at 16:41:37.

```
16:42:58 Served by: AWS | App tier says: {"db_result
16:43:00 Served by: AWS | App tier says: {"db_result
16:43:02 Served by: Azure | App tier says: {"db_result
16:43:05 Served by: Azure | App tier says: {"db_result
```

Result: first answer from Azure at 16:43:02, about 85 seconds after the start, with no user-visible errors.

## Notes
- RTO: about 96 seconds (failover). The delay is Front Door waiting for enough failed health probes.
- RPO: not measured. The databases are separate in each cloud and do not replicate; the S3 to Lambda to RDS sync is the only data path (AWS).
- The excerpt above is the part of the loop output captured in the session; the full terminal log is on the laptop.
