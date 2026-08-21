#!/usr/bin/env python3
"""Generate the percona.company fixture used by questions 2, 6 and 10.

The collection has to be big enough that a COLLSCAN on the question 6
query costs real milliseconds, so the candidate sees a difference in
`explain("executionStats")` before and after indexing. 100k documents is
about 15 MB of JSON (4 MB gzipped), which still imports in a couple of
seconds inside the container.

Deterministic: same seed, same file, so every image rebuild ships the
same data.

Usage:
    python3 tools/gen-company.py                 # regenerate all 3 tarballs
    python3 tools/gen-company.py --count 50000
    python3 tools/gen-company.py --out /tmp/company.json --no-tar
"""
import argparse
import json
import pathlib
import random
import subprocess
import tempfile

FIRST = ["Ana", "Carlos", "Ingrid", "Jane", "Jeremy", "Jerome", "Jerry",
         "Joan", "John", "Liu", "Maria", "Mark", "Omar", "Priya", "Sarah",
         "Sora", "Wei"]
LAST = ["Chen", "Garcia", "Jones", "Khan", "Kim", "Mendez", "Müller",
        "Nguyen", "Olsson", "Park", "Patel", "Rossi", "Silva", "Smith",
        "Tanaka"]
INDUSTRY = ["Education", "Energy", "Finance", "Healthcare", "Logistics",
            "Manufacturing", "Media", "Pharma", "Retail", "Tech"]
FIRM = ["Corp", "GmbH", "Group", "Holdings", "Inc", "LLC", "Ltd", "SA"]
COUNTRY = ["AR", "BR", "CN", "DE", "ES", "FR", "IN", "JP", "UK", "US"]

# Questions that ship the dataset as /opt/company.json.tar.gz.
TARGETS = ["exercises/02-import-company",
           "exercises/06-missing-index",
           "exercises/10-restore-backup"]


def documents(count, seed):
    rnd = random.Random(seed)
    for i in range(count):
        yield {
            "_id": i,
            "name": f"Company-{i:06d}",
            "CEO": f"{rnd.choice(FIRST)} {rnd.choice(LAST)}",
            "founded": rnd.randint(1900, 2024),
            "employees": rnd.randint(20, 50000),
            "industry": rnd.choice(INDUSTRY),
            "firm": rnd.choice(FIRM),
            "country": rnd.choice(COUNTRY),
        }


def write_json(path, count, seed):
    with open(path, "w", encoding="utf-8") as fh:
        for doc in documents(count, seed):
            fh.write(json.dumps(doc, ensure_ascii=False) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=100000)
    ap.add_argument("--seed", type=int, default=20260818)
    ap.add_argument("--out", default=None,
                    help="write company.json here instead of the tarballs")
    ap.add_argument("--no-tar", action="store_true")
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent

    if args.out:
        write_json(args.out, args.count, args.seed)
        print(f"{args.out}: {args.count} documents")
        if args.no_tar:
            return

    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "company.json"
        write_json(src, args.count, args.seed)
        for target in TARGETS:
            dest = root / target / "company.json.tar.gz"
            subprocess.run(["tar", "-czf", str(dest),
                            "-C", str(src.parent), src.name], check=True)
            size = dest.stat().st_size / 1024 / 1024
            print(f"{dest.relative_to(root)}: {args.count} documents, {size:.1f} MB")


if __name__ == "__main__":
    main()
