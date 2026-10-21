# Week 4 - Storage and databases

The labs ran in `us-east-2` on October 21, 2026, matching the Region used for my Week 3 EC2 work. The [decision guide](decision-guide.md) compares S3, EBS, EFS, RDS, and DynamoDB.

## Lab 4.1 - S3 lifecycle

I created the private `my-training-bucket-zoey` bucket and uploaded `week-03/runbook.md` as `runbook.md`. `aws s3 ls` returned the 5,524-byte object. All four S3 Block Public Access controls were enabled. The [lifecycle configuration](lifecycle.json) has an enabled `archive-after-30-days` rule that transitions objects to S3 Glacier Flexible Retrieval (`GLACIER`) after 30 days. I used the `varies_by_storage_class` minimum-size behavior because the runbook is smaller than 128 KiB; otherwise a newly configured rule would not transition that object. The rule was verified through `get-bucket-lifecycle-configuration`. The object remained in S3 Standard during this short lab and was deleted before any transition.

## Lab 4.2 - Private RDS MySQL and data governance

I used MySQL 8.0.46 on a single-AZ `db.t3.micro` RDS instance named `training-db` with 20 GiB of encrypted storage, no public endpoint, no automated backups, and a managed master password. Its security group accepted TCP 3306 only from a temporary EC2 connector security group in the same VPC. The connector accepted SSH only from my current `/32` address. I used an SSH tunnel and verified TLS to the RDS CA from my local MySQL client. The raw dump was transferred from the provided server using certificate-verified FTPS and kept outside this Git repository; it was never uploaded to S3 or copied to EC2.

The supplied dump contained 55,212 one-row `INSERT` statements. To avoid a slow cross-network round trip for each statement, [batch-dump.py](batch-dump.py) combined them into 553 statements without changing the rows. I imported the resulting dump into a temporary `training_data` database, then immediately ran [sanitize.sql](sanitize.sql). The source had identifying fields beyond the 17 listed in the handbook, including the original MLS display ID, free-text remarks, office information, photos, and the original row ID. The script copied only seven fields needed by PropertyLite and the labs, generated new IDs ordered by the source row ID, and dropped the raw table.

Verification after sanitization:

| Check | Result |
| --- | --- |
| Retained rows | 55,212 |
| Columns | `L_ListingID`, `L_City`, `L_Keyword2`, `LM_Dec_3`, `LM_Int2_3`, `L_SystemPrice`, `L_Status` |
| IDs failing `^R1[0-9]+$` | 0 |
| Original table or temporary copy remaining | 0 |
| Aggregate query | Returned city counts and average prices; highest count was Los Angeles with 4,015 listings |

The reduced table is suitable for this exercise's specified columns; synthetic IDs and field removal do not by themselves prove that combinations of property attributes are impossible to reidentify.

### Connection timeout drill

If the MySQL client times out, I would check that the EC2 connector and RDS instance are in the same VPC, then confirm the RDS security group's TCP 3306 ingress source is the connector's security group ID. I would also confirm the tunnel is up and the RDS instance is `available`. In this run, the connection succeeded; the timeout was a troubleshooting scenario, not an observed failure.

## Lab 4.3 - DynamoDB

I created the `Properties` table with `L_ListingID` as its string partition key and `PAY_PER_REQUEST` billing. I inserted one row selected from the cleaned RDS table: synthetic ID `R100001`, city Beverly Hills, four bedrooms, and list price 3,950,000. A consistent `get-item` read returned the same attributes. The ID came from the sanitized import, not from the Week 0 sample CSV.

## Cleanup

After the checks, I deleted the DynamoDB table, removed the S3 lifecycle rule and Standard-class object, and deleted the empty bucket. I deleted `training-db` without a final snapshot, terminated the temporary EC2 connector, stopped the local SSH tunnel, and deleted both lab security groups and the DB subnet group. I also deleted the local raw and batched SQL files, private logs, and temporary item files. Follow-up CLI checks returned no `training-db`, no `Properties` table, no training bucket, a `terminated` EC2 instance, and no RDS-managed secret.

The Billing dashboard screenshot needs to be added after account sign-in and MFA. AWS billing data can lag resource deletion, so the absence of lab resources is the cleanup verification recorded here.
