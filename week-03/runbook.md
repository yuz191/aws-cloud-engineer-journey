# Week 3 runbook — PropertyLite on EC2

Verified in the EC2 console on October 14, 2026: `property-api-01` is instance `i-0cddf25b01bf5135c`, running as `t3.micro` in `us-east-2a`, with key pair `training-key`. Its current public IPv4 address is `18.119.140.165`. This auto-assigned address can change after a stop/start, so check the console before future connection attempts.

## Deployment

1. In the Ohio Region (`us-east-2`), I launched an Amazon Linux 2023 EC2 instance named `property-api-01` using `t3.micro`. The EC2 console shows AMI `al2023-ami-2023.12.20261013.0-kernel-6.18-x86_64`.
2. I selected the `training-key` key pair at launch. I stored the downloaded private key outside this Git repository and restricted its Windows ACL to my account's read permission before using it.
3. I created security group `sg-072bc5dddbcf206e8` with two inbound rules: SSH/TCP 22 from my public IPv4 address as a `/32` (“My IP” at launch), and Custom TCP 8080 from `0.0.0.0/0` so PropertyLite can be reached over the internet. I did not open port 80 for this app.
4. I pasted [the bootstrap script](../propertylite/ec2-user-data.sh) into Advanced details → User data. It installs Python and Flask, writes the app and sample CSV to `/opt/property-api`, and starts a `propertylite` systemd service. This service starts the app again after a reboot. I verified that the instance's EC2 **Current user data** field contains the complete script.
5. After launch, I checked that the instance was `running`, recorded its current Public IPv4 address, and allowed a few minutes for first-boot setup. EC2 shows `3/3 checks passed`.

## Verify PropertyLite

From my local PowerShell terminal, I ran these commands with the instance's **current** public IP. On October 14, the address was `18.119.140.165`; `18.119.149.165` is a different address and timed out in a browser tab.

```bash
curl http://18.119.140.165:8080/health
curl http://18.119.140.165:8080/properties/R100234
```

Both requests returned HTTP 200. `/health` returned `{"status":"ok"}`; the listing endpoint returned the Sacramento record with listing ID `R100234`. In PowerShell, `curl` displayed a formatted `Invoke-WebRequest` response rather than only the raw JSON body.

Evidence: [health response](curl-health.png) and [listing response](curl-listing.png), captured from the local PowerShell terminal.

## Connect with SSH

I connected from Windows using the downloaded key. Windows OpenSSH checks NTFS ACLs, so I removed inherited access and gave only my account read access before connecting:

```powershell
$KeyPath = '<path-to-training-key.pem>'
icacls $KeyPath /inheritance:r /grant:r "$($env:USERDOMAIN)\$($env:USERNAME):(R)"
ssh.exe -i $KeyPath ec2-user@18.119.140.165
```

**Verified:** The ACL now lists only my Windows account with read permission, and an SSH login check returned `SSH_CONNECTED` on October 14, 2026. These commands run on my computer, not in EC2 User data.

## EBS snapshot

I selected the instance's root EBS volume in EC2 → Volumes and created a snapshot. AWS returned snapshot ID `snap-0128b251b59665928` from volume `vol-04f5da16459931976`.

**Verified:** EC2 → Snapshots shows `Completed` and `100%` for this snapshot. The source volume details show it attached to `property-api-01` as `/dev/xvda` (EBS card index 0), confirming it is the root volume.

Creating a new EBS volume from this snapshot would restore the root volume's data as captured at snapshot time. The new volume could then be attached to a compatible instance in the same Availability Zone as that new volume.

## SSH timeout troubleshooting exercise

If SSH hangs and times out, I would first confirm that the instance is running and that I am using its current public IP. Then I would compare my current public IP (`curl ifconfig.me`) with the security group's TCP 22 source. If they differ, I would edit the inbound SSH rule to use my current IP. I would also check the subnet's route to an internet gateway if the IP rule is correct. Selecting “My IP” at launch stores an IP/CIDR value; it does not update automatically when my laptop's public IP changes.

**Observed:** SSH to the correct IP succeeded. A browser attempt to `18.119.149.165` timed out because it differs from the instance's actual IP `18.119.140.165`; this was an address typo, not a demonstrated stale “My IP” rule. The stale-rule checks above are the troubleshooting procedure for the lab scenario.

## Cleanup

After recording the curl screenshot and verifying the snapshot is complete, terminate `property-api-01` in EC2 → Instances. This permanently removes the instance. The instance's Storage tab currently shows **Delete on termination: Yes** for root volume `vol-04f5da16459931976`. After termination, return to EC2 → Volumes and confirm that this volume was deleted. If it remains, investigate before removing the unused volume.

**Status to record:** Instance termination and root-volume deletion have not been verified in this runbook. The snapshot is a separate resource and remains until it is deleted; decide when to remove it after the exercise and any required review.
