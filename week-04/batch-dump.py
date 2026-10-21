"""Combine one-row INSERT statements from the supplied dump for faster RDS import.

The output still contains raw identifying data. Keep both files outside Git and
delete both after the sanitized table has been verified.
"""

import argparse
from pathlib import Path


def batch_dump(source: Path, destination: Path, batch_size: int = 100) -> tuple[int, int]:
    if source.resolve() == destination.resolve():
        raise ValueError("source and destination must differ")

    prefix = None
    tuples = []
    row_count = 0
    statement_count = 0

    with source.open("rb") as incoming, destination.open("wb") as outgoing:
        def flush() -> None:
            nonlocal statement_count, tuples
            if tuples:
                outgoing.write(prefix + b",".join(tuples) + b";\n")
                statement_count += 1
                tuples = []

        for line in incoming:
            if not line.startswith(b"INSERT INTO "):
                flush()
                outgoing.write(line)
                continue

            marker = line.find(b" VALUES(")
            value = line[marker + len(b" VALUES") :].rstrip(b"\r\n")
            if marker < 0 or not value.startswith(b"(") or not value.endswith(b");"):
                raise ValueError("Unexpected INSERT format; batch output is incomplete")

            new_prefix = line[: marker + len(b" VALUES")]
            if prefix is not None and new_prefix != prefix:
                flush()
            prefix = new_prefix
            tuples.append(value[:-1])
            row_count += 1
            if len(tuples) >= batch_size:
                flush()

        flush()

    return row_count, statement_count


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    rows, statements = batch_dump(args.source, args.destination)
    print(f"Preserved {rows} rows in {statements} batched INSERT statements")
