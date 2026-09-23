# AWS Cloud Engineer Journey

Week 0 environment setup and the PropertyLite starter application from the IDX Exchange AWS Cloud Engineer Intern Handbook.

## PropertyLite

Open Ubuntu with `wsl -d Ubuntu`, then run:

```bash
cd /mnt/d/UIUC/career/IDX_Exchange/aws-cloud-engineer-journey/propertylite
source ~/.venvs/propertylite/bin/activate
python3 app.py
```

In another terminal:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/properties
curl http://localhost:8080/properties/R100234
```

The sample data is for local training. The application reads `PROPERTY_DATA_PATH` when set, otherwise `rets_property_sample.csv` in the current directory.

## Week 0 checklist

- [ ] AWS personal account created and console login verified (requires account owner)
- [x] Ubuntu WSL 2, AWS CLI, Git, VS Code extensions, and Terraform verified
- [ ] GitHub repository created and this project pushed (requires GitHub account access)
- [x] All three PropertyLite endpoints return JSON

Ubuntu is installed in `D:\Program Files\Ubuntu` and opens as user `yuz191`. Its password must be set privately with `wsl -d Ubuntu -u root passwd yuz191` in PowerShell before using `sudo`. The AWS account signup requires the account owner's personal information, payment method, and agreement acceptance.

Do not commit AWS credentials, access keys, or personal account recovery information.
