#!/usr/bin/env python3
"""

versions_cleaning.py — clean & deduplicate tool versions from pipeline logs.

Input example (mixed, unordered, with repeated tool groups):
"QUAST":
    quast: 5.3.0
"BUSCO":
    busco: 5.8.2
"KRAKEN2":
    kraken2: 2.1.5
    pigz: 2.4
...

What this script keeps:
quast: 5.3.0
busco: 5.8.2
kraken2: 2.1.5
pigz: 2.4
fastp: 0.24.0
ktImportTaxonomy: 2.8.1
spades: 4.0.0

Usage:
    module load biopythontools # this environment contains many basic python packages

  # from file -> YAML (default)
  python versions_cleaning.py -i pipeline_versions.txt -o clean_versions.yaml

  # read stdin, write TSV, keep first occurrence per tool
  cat pipeline_versions.txt | python versions_cleaning.py -o versions.tsv -f tsv --strategy first
"""

import argparse
import json
import sys
from collections import OrderedDict

def parse_args():
    ap = argparse.ArgumentParser(
        description="Deduplicate tool versions; drop quoted tool-group lines.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("-i", "--input", default="-", help="Input file path or '-' for stdin")
    ap.add_argument("-o", "--output", default="-", help="Output file path or '-' for stdout")
    ap.add_argument(
        "-f", "--format",
        choices=["yaml", "tsv", "json"],
        default="yaml",
        help="Output format"
    )
    ap.add_argument(
        "--strategy",
        choices=["last", "first"],
        default="last",
        help="If a tool appears multiple times with possibly different versions"
    )
    ap.add_argument(
        "--sort",
        choices=["alpha", "as_seen"],
        default="alpha",
        help="Sort tools alphabetically or keep encounter order"
    )
    return ap.parse_args()

def iter_lines(path):
    if path == "-":
        for line in sys.stdin:
            yield line.rstrip("\n")
    else:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                yield line.rstrip("\n")

def dedupe(lines, strategy="last", keep_order="alpha"):
    """
    Return mapping tool -> version (single string), skipping lines like:  "QUAST":
    Accept any line with 'key: value' where key is NOT quoted.
    """
    # Ordered to preserve first/last behavior deterministically
    mapping = OrderedDict()

    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        # skip quoted tool-group headers like: "QUAST":
        if line.startswith('"') and line.endswith('":'):
            continue
        # skip bare headers like QUAST: (rare), but keep real key: value pairs
        if ":" not in line:
            continue

        key, val = line.split(":", 1)
        key = key.strip()
        val = val.strip()

        # ignore quoted keys (e.g., "SPADES")
        if key.startswith('"') and key.endswith('"'):
            continue
        if not key or not val:
            continue

        if strategy == "first":
            if key not in mapping:
                mapping[key] = val
        else:  # last
            mapping[key] = val

    # Sorting
    if keep_order == "alpha":
        mapping = OrderedDict(sorted(mapping.items(), key=lambda kv: kv[0].lower()))

    return mapping

def dump(mapping, fmt="yaml"):
    if fmt == "json":
        return json.dumps(mapping, indent=2) + "\n"
    if fmt == "tsv":
        lines = ["tool\tversion"]
        lines += [f"{k}\t{v}" for k, v in mapping.items()]
        return "\n".join(lines) + "\n"
    # yaml (simple)
    # Avoid importing PyYAML; emit plain YAML-like text.
    out = []
    for k, v in mapping.items():
        out.append(f"{k}: {v}")
    return "\n".join(out) + "\n"

def main():
    args = parse_args()
    mapping = dedupe(
        iter_lines(args.input),
        strategy=args.strategy,
        keep_order=args.sort,
    )
    text = dump(mapping, args.format)

    if args.output == "-":
        sys.stdout.write(text)
    else:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text)

if __name__ == "__main__":
    main()