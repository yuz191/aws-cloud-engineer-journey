# AWS Cloud Engineer Journey

Week 0 environment setup and the PropertyLite starter application from the IDX Exchange AWS Cloud Engineer Intern Handbook.

The setup record is in [week-00](week-00/README.md). The reusable application stays in [propertylite](propertylite/) so later weeks can deploy the same code.

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

- [x] AWS personal account created and console login verified
- [x] Ubuntu WSL 2, AWS CLI, Git, VS Code extensions, and Terraform verified
- [x] GitHub repository created and this project pushed
- [x] All three PropertyLite endpoints return JSON

Ubuntu is installed in `D:\Program Files\Ubuntu` and opens as user `yuz191`. The account owner set its password privately, so `sudo` is available when needed.

Do not commit AWS credentials, access keys, or personal account recovery information.
