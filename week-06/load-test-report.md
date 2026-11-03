# Week 6 load-test report — PropertyLite behind an ALB and ASG

Tested on November 3, 2026 in AWS Ohio (`us-east-2`). Times below are Central Standard Time (CST, UTC−06:00); the CloudWatch graph axes show UTC.

## Lab configuration

| Component | Configuration |
| --- | --- |
| VPC | Recreated `training-vpc`, `10.0.0.0/16`, with public and private subnets in `us-east-2a` and `us-east-2b`. Public subnets route through an internet gateway; both private subnets route outbound through one NAT gateway. |
| Launch template | Existing `property-api-template`, updated to version 2. Amazon Linux 2023, `t3.micro`, full [`ec2-user-data.sh`](../propertylite/ec2-user-data.sh), one-minute EC2 monitoring, an instance security group, and a Systems Manager instance profile. Version 1 lacked user data and a security group, so it could not bootstrap PropertyLite in this VPC. |
| Target group | `property-api-week6-tg`, instance targets, HTTP port 8080, health check path `/health`. |
| ALB | Internet-facing `property-api-week6-alb` in both **public** subnets. HTTP listener on port 80 forwards to the target group. Its security group permits inbound TCP 80. |
| ASG | `property-api-week6-asg` in both **private** subnets, attached to the target group. Desired/min/max capacity: **2/1/4**. Instance security group permits TCP 8080 only from the ALB security group. |
| Scaling | Target tracking on **ASG average CPU utilization**, target **50%**. One-minute ASG metrics were enabled for the capacity graph. |

The private instances had no public IP addresses. Systems Manager ran the test commands on them, so this lab did not need a bastion. The single NAT gateway provided outbound access for the bootstrap package installs and Systems Manager; it is a lab setup rather than a multi-AZ NAT design.

## Application and self-healing checks

The ALB DNS name was `property-api-week6-alb-1845787657.us-east-2.elb.amazonaws.com`. `GET /health` returned HTTP 200 with `{"status":"ok"}`, and `GET /properties` returned the three sample listings. Both initial targets were healthy.

At first creation, AWS's new Auto Scaling service-linked role was not ready, so two initial launch attempts failed. A retry of the scaling policy succeeded after role propagation, and the ASG launched two healthy instances. The failed attempts remain visible in the raw activity record.

I terminated instance `i-0305cc35ed36726d0` at **5:12:09 PM**. The ASG began launching replacement `i-0d8f38a0434db22c6` at **5:12:53 PM**, about **44 seconds** later. The replacement completed bootstrap, passed `/health`, and became healthy in the target group. The [scaling activity record](evidence/scaling-activities.json) distinguishes this replacement from the later CPU-driven scale-out.

## CPU load test and scale-out

Systems Manager ran `sudo dnf install -y stress-ng` followed by `stress-ng --cpu 2 --timeout 600s` on both ASG instances, starting at **5:16:21 PM**. I cancelled the command after scale-out. This uses `dnf` because Amazon Linux 2023 does not include the handbook's `amazon-linux-extras` command; [AWS documents `stress-ng` for AL2023](https://docs.aws.amazon.com/linux/al2023/ug/epel.html).

| Observation | CST timestamp | Evidence |
| --- | --- | --- |
| Pre-test ASG average CPU | 5:16:00 PM — **0.19%** | [CPU metric data](evidence/cpu-metrics.json) |
| First one-minute CPU datapoint above 50% | **5:17:00 PM — 96.81%** | [CloudWatch CPU graph](evidence/cloudwatch-cpu.png) |
| Three consecutive high datapoints | 5:17–5:19 PM — 96.81%, 100.00%, 99.98% | [High CPU alarm](evidence/high-cpu-alarm.json) |
| Target tracking alarm changed desired capacity **2 → 4** | **5:20:42 PM** | [Scaling activity](evidence/scaling-activities.json) |
| New instance launches began | 5:20:55–5:20:56 PM | [Scaling activity](evidence/scaling-activities.json) |
| CloudWatch first reported desired capacity **4** | 5:21:00 PM | [CloudWatch capacity graph](evidence/cloudwatch-scaleout.png) |

**Measured gap:** 5:20:42 PM − 5:17:00 PM = **3 minutes 42 seconds** from the first high CPU metric minute to the ASG policy action. The CPU metric has one-minute resolution; the scaling activity records the action to the second. The capacity graph reports the change in its next one-minute bucket.

### CloudWatch evidence

These PNGs are metric snapshots returned by Amazon CloudWatch's [GetMetricWidgetImage API](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_GetMetricWidgetImage.html). The raw metric and activity JSON files are included above for timestamp verification.

![CloudWatch ASG average CPU rose above the 50 percent target](evidence/cloudwatch-cpu.png)

![CloudWatch ASG desired capacity rose from two to four instances](evidence/cloudwatch-scaleout.png)

After scaling, **all four targets passed ALB health checks**; see the [target health snapshot](evidence/target-health.json). The ALB continued to serve `/health` and `/properties`.

## Cleanup

After saving the evidence, I deleted the ASG and its instances, the ALB, target group, launch template, temporary Systems Manager instance profile and role, NAT gateway and Elastic IP, and the recreated `training-vpc` with its subnets and routes. Cleanup completed at **5:36:21 PM CST**. Independent AWS queries found no Week 6 ASG, load balancer, target group, launch template, Elastic IP, or instance profile; only the pre-existing default VPC remained, and all four final test instances were `terminated`.
