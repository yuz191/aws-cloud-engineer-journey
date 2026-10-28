"""Render the Week 5 AWS network diagram without requiring a diagram service."""

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch


OUT = Path(__file__).with_name("vpc-diagram.png")
fig, ax = plt.subplots(figsize=(16, 10), dpi=150)
fig.patch.set_facecolor("#f8fafc")
ax.set_facecolor("#f8fafc")
ax.set_xlim(0, 16)
ax.set_ylim(0, 10)
ax.axis("off")


def box(x, y, w, h, fill, edge, radius=0.12, lw=1.6):
    patch = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0.02,rounding_size={radius}",
        facecolor=fill, edgecolor=edge, linewidth=lw,
    )
    ax.add_patch(patch)


def label(x, y, text, size=12, color="#0f172a", weight="normal", ha="left"):
    ax.text(x, y, text, fontsize=size, color=color, weight=weight,
            ha=ha, va="center", family="DejaVu Sans")


def arrow(start, end, color, lw=2.5, style="-", mutation=14, rad=0):
    patch = FancyArrowPatch(start, end, arrowstyle="-|>", mutation_scale=mutation,
                            color=color, linewidth=lw, linestyle=style,
                            connectionstyle=f"arc3,rad={rad}")
    ax.add_patch(patch)


blue = "#2563eb"
orange = "#ea580c"
slate = "#475569"

label(0.6, 9.58, "Week 5  |  Custom VPC and bastion access", 21, "#0f172a", "bold")
label(0.6, 9.15, "Ohio (us-east-2)  •  VPC 10.0.0.0/16  •  2 Availability Zones", 11, slate)

box(3.55, 0.75, 11.85, 8.0, "#ffffff", "#64748b", radius=0.22, lw=2)
label(3.88, 8.48, "training-vpc", 15, "#334155", "bold")

box(4.15, 1.18, 5.15, 6.93, "#f8fafc", "#cbd5e1")
box(9.66, 1.18, 5.15, 6.93, "#f8fafc", "#cbd5e1")
label(4.43, 7.82, "Availability Zone A  •  us-east-2a", 12, "#334155", "bold")
label(9.95, 7.82, "Availability Zone B  •  us-east-2b", 12, "#334155", "bold")

box(4.45, 4.94, 4.55, 2.55, "#eff6ff", "#93c5fd")
box(9.96, 4.94, 4.55, 2.55, "#eff6ff", "#93c5fd")
box(4.45, 1.56, 4.55, 2.98, "#f0fdf4", "#86efac")
box(9.96, 1.56, 4.55, 2.98, "#f0fdf4", "#86efac")

label(4.70, 7.16, "Public subnet A  •  10.0.0.0/20", 11, "#1d4ed8", "bold")
label(10.20, 7.16, "Public subnet B  •  10.0.16.0/20", 11, "#1d4ed8", "bold")
label(4.70, 4.22, "Private subnet A  •  10.0.128.0/20", 11, "#15803d", "bold")
label(10.20, 4.22, "Private subnet B  •  10.0.144.0/20", 11, "#15803d", "bold")

box(4.75, 5.85, 2.05, 0.92, "#dbeafe", blue, radius=0.1)
label(5.78, 6.40, "Bastion EC2", 11, "#1e3a8a", "bold", "center")
label(5.78, 6.10, "public IPv4", 9, "#1e40af", ha="center")
box(7.11, 5.85, 1.58, 0.92, "#ffedd5", orange, radius=0.1)
label(7.90, 6.40, "NAT Gateway", 10, "#9a3412", "bold", "center")
label(7.90, 6.10, "Elastic IP", 9, "#9a3412", ha="center")
label(4.70, 5.23, "0.0.0.0/0 → Internet Gateway", 9, slate)
label(10.20, 5.23, "0.0.0.0/0 → Internet Gateway", 9, slate)

box(4.82, 2.69, 2.24, 0.94, "#dcfce7", "#16a34a", radius=0.1)
label(5.94, 3.25, "Private EC2", 11, "#166534", "bold", "center")
label(5.94, 2.96, "private IPv4 only", 9, "#166534", ha="center")
label(4.70, 2.13, "0.0.0.0/0 → NAT Gateway", 9, slate)
label(10.20, 3.33, "No public IPv4", 10, slate)
label(10.20, 2.13, "0.0.0.0/0 → NAT Gateway", 9, slate)

box(0.56, 5.64, 1.70, 0.88, "#e2e8f0", "#64748b")
label(1.41, 6.16, "Laptop", 11, "#334155", "bold", "center")
label(1.41, 5.88, "SSH agent", 9, slate, ha="center")
box(2.57, 5.64, 0.82, 0.88, "#fef3c7", "#d97706")
label(2.98, 6.10, "IGW", 11, "#92400e", "bold", "center")

arrow((2.27, 6.05), (2.55, 6.05), blue)
arrow((3.40, 6.05), (4.72, 6.05), blue)
arrow((5.75, 5.83), (5.91, 3.65), blue, rad=0.15)
label(4.02, 5.02, "SSH 22", 9, blue)
label(6.17, 4.67, "SSH 22, source = bastion SG", 9, blue)

arrow((7.10, 3.16), (7.87, 5.82), orange, rad=0.10)

box(0.58, 1.49, 2.92, 3.21, "#ffffff", "#cbd5e1")
label(0.82, 4.32, "Security + routing", 12, "#334155", "bold")
label(0.82, 3.78, "Bastion SG:", 10, "#1e40af", "bold")
label(0.82, 3.45, "SSH 22 from laptop /32", 9, slate)
label(0.82, 2.94, "Private SG:", 10, "#15803d", "bold")
label(0.82, 2.61, "SSH 22 from bastion SG", 9, slate)
label(0.82, 2.08, "Agent forwarding; private key", 9, slate)
label(0.82, 1.77, "stays on the laptop", 9, slate)

label(0.58, 0.43, "BLUE: laptop → bastion → private instance (SSH)       ORANGE: private instance → NAT → IGW → internet (egress)", 10, slate)
fig.savefig(OUT, dpi=150, bbox_inches="tight", pad_inches=0.15,
            facecolor=fig.get_facecolor())
print(OUT)
