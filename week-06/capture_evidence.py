"""Save AWS CloudWatch metric snapshots and raw Week 6 observations."""

from __future__ import annotations

import base64
import json
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "evidence"
EVIDENCE.mkdir(exist_ok=True)
REGION = "us-east-2"
ASG = "property-api-week6-asg"


def aws(*args: str) -> dict:
    result = subprocess.run(
        ["aws", *args, "--region", REGION, "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def save(name: str, data: dict) -> None:
    (EVIDENCE / name).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


state = {}
for line in (HERE / ".lab-state").read_text(encoding="utf-8").splitlines():
    key, _, value = line.partition("=")
    state[key] = value

stress_at = datetime.fromisoformat(state["STRESS_START_UTC"].replace("Z", "+00:00"))
start = stress_at - timedelta(minutes=8)
end = datetime.now(timezone.utc) + timedelta(minutes=1)

cpu = aws(
    "cloudwatch", "get-metric-statistics", "--namespace", "AWS/EC2",
    "--metric-name", "CPUUtilization", "--dimensions",
    f"Name=AutoScalingGroupName,Value={ASG}", "--start-time", iso(start),
    "--end-time", iso(end), "--period", "60", "--statistics", "Average",
)
capacity = aws(
    "cloudwatch", "get-metric-statistics", "--namespace", "AWS/AutoScaling",
    "--metric-name", "GroupDesiredCapacity", "--dimensions",
    f"Name=AutoScalingGroupName,Value={ASG}", "--start-time", iso(start),
    "--end-time", iso(end), "--period", "60", "--statistics", "Maximum",
)
activities = aws(
    "autoscaling", "describe-scaling-activities", "--auto-scaling-group-name", ASG,
    "--max-items", "100",
)
ssm = aws("ssm", "list-command-invocations", "--command-id", state["STRESS_COMMAND"], "--details")
alarm = aws(
    "cloudwatch", "describe-alarms", "--alarm-name-prefix",
    f"TargetTracking-{ASG}-AlarmHigh",
)
targets = aws("elbv2", "describe-target-health", "--target-group-arn", state["TARGET_GROUP"])

cpu["Datapoints"].sort(key=lambda x: datetime.fromisoformat(x["Timestamp"]))
capacity["Datapoints"].sort(key=lambda x: datetime.fromisoformat(x["Timestamp"]))
save("cpu-metrics.json", cpu)
save("desired-capacity-metrics.json", capacity)
save("scaling-activities.json", activities)
save("stress-command.json", ssm)
save("high-cpu-alarm.json", alarm)
save("target-health.json", targets)


def widget_image(filename: str, widget: dict) -> None:
    result = subprocess.run(
        ["aws", "cloudwatch", "get-metric-widget-image", "--region", REGION,
         "--metric-widget", json.dumps(widget), "--output-format", "png", "--output", "text"],
        check=True, capture_output=True, text=True,
    )
    (EVIDENCE / filename).write_bytes(base64.b64decode(result.stdout.strip()))


base = {
    "width": 1200,
    "height": 500,
    "view": "timeSeries",
    "stacked": False,
    "region": REGION,
    "period": 60,
    "start": iso(start),
    "end": iso(end),
    "timezone": "+0000",
}
widget_image("cloudwatch-cpu.png", {
    **base,
    "title": "ASG average CPU utilization",
    "metrics": [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", ASG,
                 {"label": "Average CPU", "stat": "Average", "period": 60}]],
    "yAxis": {"left": {"min": 0, "max": 100}},
    "annotations": {"horizontal": [{"label": "50% target", "value": 50, "color": "#d62728"}]},
})
widget_image("cloudwatch-scaleout.png", {
    **base,
    "title": "ASG desired capacity (scale-out)",
    "metrics": [["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", ASG,
                 {"label": "Desired instances", "stat": "Maximum", "period": 60}]],
    "yAxis": {"left": {"min": 0, "max": 4}},
})

spikes = [p for p in cpu["Datapoints"] if datetime.fromisoformat(p["Timestamp"]) >= stress_at and p["Average"] > 50]
scaleouts = [a for a in activities["Activities"] if datetime.fromisoformat(a["StartTime"]) >= stress_at
             and "Launching a new EC2 instance" in a["Description"]]
print(json.dumps({
    "stress_start_utc": iso(stress_at),
    "cpu_points": len(cpu["Datapoints"]),
    "capacity_points": len(capacity["Datapoints"]),
    "first_cpu_above_50": spikes[0] if spikes else None,
    "first_post_stress_launch": scaleouts[-1] if scaleouts else None,
    "latest_cpu_points": cpu["Datapoints"][-8:],
    "latest_capacity_points": capacity["Datapoints"][-8:],
}, indent=2))
