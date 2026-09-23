# Week 1 - Cloud fundamentals and account setup

The AWS account root user is the original identity created with the account and has access to nearly every account setting and resource. Because it is so powerful, I enabled MFA for root and will use it only for tasks that require root credentials. My IAM user, `Zoey-admin`, is a separate identity for routine console and CLI work. IAM permissions are controlled through policies, so an IAM user can be limited to the actions it needs, even though my training admin user currently has broad permissions. I checked `aws sts get-caller-identity` and confirmed that my CLI session uses the IAM user rather than root. In the Shared Responsibility Model, AWS protects the facilities, hardware, networking, and foundational software that run its cloud. I am responsible for how I configure my account and workloads, including access controls, MFA, data protection, and updates to operating systems I manage.

## Evidence

- [Root MFA enabled](Screenshot-of-mfa.png)
- [Training budget created](Screenshot-of-budgets.png)

## References

- [AWS root user best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html)
- [AWS IAM users](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html)
- [AWS Shared Responsibility Model](https://aws.amazon.com/compliance/shared-responsibility-model/)
