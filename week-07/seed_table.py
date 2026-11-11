"""Load PropertyLite's approved seven-column training CSV into DynamoDB."""

import argparse
import csv
import json
import subprocess
from pathlib import Path


FIELDS = (
    "L_ListingID", "L_City", "L_Keyword2", "LM_Dec_3",
    "LM_Int2_3", "L_SystemPrice", "L_Status",
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", default="us-east-2")
    parser.add_argument("--csv", type=Path, default=Path(__file__).resolve().parent.parent / "propertylite" / "rets_property_sample.csv")
    args = parser.parse_args()
    with args.csv.open(newline="", encoding="utf-8") as source:
        reader = csv.DictReader(source)
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError("Unexpected CSV columns; refusing to upload data")
        count = 0
        for row in reader:
            item = {field: {"S": row[field]} for field in FIELDS}
            subprocess.run(
                ["aws", "dynamodb", "put-item", "--region", args.region,
                 "--table-name", "Properties", "--item", json.dumps(item)],
                check=True,
            )
            count += 1
    print(f"Loaded {count} approved training listings into Properties")


if __name__ == "__main__":
    main()
