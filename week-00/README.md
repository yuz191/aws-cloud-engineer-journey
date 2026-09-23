# Week 0 - Environment setup

## Completed

- AWS account: console sign-in verified.
- Ubuntu: WSL 2 installed at `D:\Program Files\Ubuntu`, with `yuz191` as the default user.
- Ubuntu tools verified: AWS CLI 2.37.1, Git 2.53.0, Terraform 1.16.4, and Python 3.14.4.
- VS Code: AWS Toolkit, HashiCorp Terraform, and WSL extensions installed.
- GitHub: [aws-cloud-engineer-journey](https://github.com/yuz191/aws-cloud-engineer-journey) created and pushed.
- PropertyLite: installed Flask 3.0.3 in `~/.venvs/propertylite`; `/health`, `/properties`, and `/properties/R100234` each returned JSON locally.

## Run the app

From PowerShell, open Ubuntu with `wsl -d Ubuntu`. Then:

```bash
cd /mnt/d/UIUC/career/IDX_Exchange/aws-cloud-engineer-journey/propertylite
source ~/.venvs/propertylite/bin/activate
python3 app.py
```

In a second Ubuntu terminal:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/properties
curl http://localhost:8080/properties/R100234
```

The application and sample data remain in the root [propertylite](../propertylite/) folder because later labs deploy that same app. No AWS access keys or account recovery information belong in this repository.
