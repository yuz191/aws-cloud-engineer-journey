# Week 4 storage and database decision guide

| Service | What it stores | Use this when... |
| --- | --- | --- |
| Amazon S3 | Objects in buckets | Files, exports, or static assets need durable object storage and can be fetched by key rather than mounted as a disk. |
| Amazon EBS | Block volumes attached to EC2 | One EC2 instance needs a low-latency boot or data volume with a filesystem. |
| Amazon EFS | Shared network filesystem | Multiple Linux compute instances need concurrent access to the same file tree. |
| Amazon RDS | Managed relational database | The application needs SQL queries, joins, constraints, and transactions without operating MySQL itself. |
| Amazon DynamoDB | Managed key-value/document table | Access patterns are known by partition key and need elastic scale with minimal database administration. |

S3 Standard suits frequently accessed objects; Standard-IA suits less frequent access with retrieval and minimum-duration costs; Glacier Flexible Retrieval suits archives that can wait for restore. A lifecycle rule automates a later storage-class transition, while versioning keeps earlier object versions after overwrite or deletion. EBS snapshots are backups of block-volume state; they do not turn EBS into a shared filesystem.

RDS Multi-AZ provides a standby in another Availability Zone for failover, not an additional read endpoint for the basic DB instance deployment. DynamoDB's partition key determines item placement and efficient key lookup; on-demand (`PAY_PER_REQUEST`) capacity charges by request, while provisioned capacity reserves throughput.
