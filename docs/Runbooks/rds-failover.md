# Runbook: RDS Failover

## Symptom

- App-level: `GenerationRequest` reads/writes start failing (`POST
  /generations` 500s, FastAPI logs show connection errors from
  `sqlalchemy`/`psycopg2`).
- `aws-ai-native-infra-dev-rds-cpu-high` or connection-related metrics
  spike right before, or an AWS-initiated failover event coincides with
  the symptom.
- **The response here is completely different depending on
  `multi_az`, and that's the whole point of the variable**:

  - **`multi_az = true` (prod's setting)**: AWS handles this
    automatically — a synchronous standby in `data-b` is promoted,
    typically within 60-120 seconds, no human action required to *recover
    the database itself*. The job here is confirming the app recovers
    cleanly, not performing the failover.
  - **`multi_az = false` (dev's actual current setting,
    `terraform.tfvars`)**: there is no standby. A primary-AZ problem is
    real, unmitigated downtime until AWS restores the instance or a
    restore-from-backup completes. This is a documented cost tradeoff,
    not a gap to "fix" reactively mid-incident — the fix (flipping
    `multi_az = true`) is a one-line, pre-planned change, not something
    to reach for during a live outage. If dev downtime here is becoming a
    genuine problem, that's a follow-up conversation about changing the
    default, not an in-the-moment escalation.

## Diagnosis

1. **Confirm what actually happened** — don't assume; check real RDS
   events:
   ```powershell
   aws rds describe-events --source-type db-instance --source-identifier aws-ai-native-infra-dev-pg --region us-east-1 --duration 120
   aws rds describe-db-instances --db-instance-identifier aws-ai-native-infra-dev-pg --region us-east-1 --query 'DBInstances[0].{MultiAZ:MultiAZ,Status:DBInstanceStatus,AZ:AvailabilityZone,SecondaryAZ:SecondaryAvailabilityZone}'
   ```
   A real failover shows up explicitly in the events feed
   (`Multi-AZ instance failover started`/`completed`) - confirm it's that,
   not something else (e.g. a security group change, a credential
   rotation) wearing the same symptoms.

2. **Is the app actually recovering, or stuck?** Both `backend/app/database.py`
   and `workers/app/database.py` create their SQLAlchemy engine with
   `pool_pre_ping=True` - this already means a stale connection (exactly
   what a failover produces, since the endpoint now points somewhere new)
   gets detected and transparently replaced on next use, not silently
   reused and failing repeatedly. If the app is still erroring well past
   AWS's own failover window, that's a real secondary problem, not just
   "waiting out the failover."

## Mitigation

- **`multi_az = true`**: monitor, don't intervene in the database layer
  itself. Watch `aws-ai-native-infra-dev-rds-cpu-high` and the app's own
  error rate; both should recover within the failover window. If the app
  doesn't recover once RDS reports healthy again, that's an app-level
  connection-handling bug to fix directly, not a reason to touch RDS
  further.
- **`multi_az = false`**: no failover to wait out. Mitigation is
  restoring service - either wait for AWS to resolve the underlying AZ
  issue, or restore from the latest automated backup
  (`backup_retention_period`, `terraform/modules/rds/variables.tf`) to a
  new instance if the outage is prolonged. This is a real decision with
  data-loss implications (anything written since the last backup) - not
  one to make unilaterally without explicit sign-off.

## Follow-up

- If dev hits this enough to be disruptive, that's the signal to revisit
  the `multi_az = false` default for dev specifically (a `terraform.tfvars`
  change, already designed for exactly this), not to route around it with
  ad hoc workarounds each time.
- Confirm `backup_retention_period` is actually long enough for how the
  environment is used day to day - the default is short (cost-driven,
  same reasoning as everything else non-prod here).
