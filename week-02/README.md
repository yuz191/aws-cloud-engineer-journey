# Week 2 - IAM and security foundations

## Policy: S3UploaderOnly-Zoey

[policies/S3UploaderOnly-Zoey.json](policies/S3UploaderOnly-Zoey.json) is an exact copy of the deployed customer-managed policy's default version (`v2`), retrieved on September 27, 2026. It is attached directly to `s3-test-user`; that user has no inline policies.

### What it allows

| Action | Permission granted by this policy |
| --- | --- |
| `s3:PutObject` | Upload a new object or overwrite an existing object at a matching key. |
| `s3:GetObject` | Read or download an object's current version at a matching key. |

Both actions are scoped to `arn:aws:s3:::my-training-bucket-zoey/*`. The trailing `/*` selects objects in that one named bucket, including objects under any prefix; it does not select the bucket resource itself or objects in other buckets. There are no conditions in this policy, so it does not further restrict object prefixes, source IPs, or encryption settings.

### Why I scoped it this way

The training user's job is to upload and retrieve files, so I listed those two actions instead of granting `s3:*` or administrator access. Limiting the resource to one training bucket keeps the intended access separate from other buckets. I included `/*` because upload and download are object-level operations. The scope includes all objects in the training bucket because the lab does not specify a narrower folder or prefix.

This policy does not grant listing all buckets (`s3:ListAllMyBuckets`), listing objects (`s3:ListBucket`), deleting objects (`s3:DeleteObject`), creating buckets, or changing bucket policies and ACLs. These omissions are not explicit Deny statements: other policies could grant additional access, while explicit denies and other AWS controls can restrict effective access.

### Lab verification

Using the separate `s3test` CLI profile, `aws sts get-caller-identity --profile s3test` returned the `s3-test-user` identity. The command below returned `AccessDenied` for the `ListBuckets` operation because no identity-based policy allowed `s3:ListAllMyBuckets`:

```bash
aws s3 ls --profile s3test
```

That is the expected least-privilege test result. It verifies the missing bucket-listing permission; it does not prove that upload and download work against a real bucket.

### Bucket-name correction completed

On September 27, 2026, I corrected the bucket name to lowercase `my-training-bucket-zoey` and saved policy version `v2` as the default. The JSON in this repository matches that deployed version. When creating the training bucket later, use this exact name if it is available; if a different name is needed, update the policy ARN to match the actual bucket before testing object operations.

## References

- [AWS S3 identity-based policy examples](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-policies-s3.html)
- [AWS S3 bucket-listing permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/list-buckets.html)
- [AWS S3 bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)
