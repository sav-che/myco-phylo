#!/usr/bin/env python3
"""
busco_logs_to_table.py — parse BUSCO *-busco.log files and compute
percentages from counts (ignores the C:… summary line).

Extracts counts:
  - Complete_C
  - Internal_stop_codons (from the "(of which ... contain internal stop codons)" note)
  - Single_copy_S
  - Duplicated_D
  - Fragmented_F
  - Missing_M
  - Total_n

Computes percentages from Total_n:
  - C_pct, S_pct, D_pct, F_pct, M_pct
  - Internal_stop_codons_pct

Usage:
  python busco_logs_to_table.py -i /path/to/busco -o busco_summary.tsv
  python busco_logs_to_table.py -i /path/to/busco -p "*-busco.log" -o out.tsv
"""

import argparse
import glob
import os
import re
from typing import Dict, Optional, List

import pandas as pd


COMPLETE_RE = re.compile(
    r"^\s*(?P<count>\d+)\s+Complete BUSCOs \(C\)"
    r"(?:\s+\(of which\s+(?P<int_stops>\d+)\s+contain internal stop codons\))?",
    re.I,
)
SINGLE_RE = re.compile(r"^\s*(?P<count>\d+)\s+Complete and single-copy BUSCOs \(S\)", re.I)
DUP_RE = re.compile(r"^\s*(?P<count>\d+)\s+Complete and duplicated BUSCOs \(D\)", re.I)
FRAG_RE = re.compile(r"^\s*(?P<count>\d+)\s+Fragmented BUSCOs \(F\)", re.I)
MISS_RE = re.compile(r"^\s*(?P<count>\d+)\s+Missing BUSCOs \(M\)", re.I)
TOTAL_RE = re.compile(r"^\s*(?P<count>\d+)\s+Total BUSCO groups searched", re.I)


def natural_sort_key(s: str):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def genome_from_filename(path: str) -> str:
    base = os.path.basename(path)
    return re.sub(r"-busco\.(?:log|txt)$", "", base, flags=re.I)


def parse_busco_log(path: str) -> Dict[str, Optional[int]]:
    rec: Dict[str, Optional[int]] = {
        "genome": genome_from_filename(path),
        "Complete_C": None,
        "Internal_stop_codons": None,
        "Single_copy_S": None,
        "Duplicated_D": None,
        "Fragmented_F": None,
        "Missing_M": None,
        "Total_n": None,
    }

    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            line = raw.strip()

            m = COMPLETE_RE.match(line)
            if m:
                rec["Complete_C"] = int(m.group("count"))
                if m.group("int_stops"):
                    rec["Internal_stop_codons"] = int(m.group("int_stops"))
                continue

            m = SINGLE_RE.match(line)
            if m:
                rec["Single_copy_S"] = int(m.group("count"))
                continue

            m = DUP_RE.match(line)
            if m:
                rec["Duplicated_D"] = int(m.group("count"))
                continue

            m = FRAG_RE.match(line)
            if m:
                rec["Fragmented_F"] = int(m.group("count"))
                continue

            m = MISS_RE.match(line)
            if m:
                rec["Missing_M"] = int(m.group("count"))
                continue

            m = TOTAL_RE.match(line)
            if m:
                rec["Total_n"] = int(m.group("count"))
                continue

    return rec


def compute_percents(df: pd.DataFrame) -> pd.DataFrame:
    # Avoid division by zero; use pandas NA-aware division.
    denom = pd.to_numeric(df["Total_n"], errors="coerce")

    for count_col, pct_col in [
        ("Complete_C", "C_pct"),
        ("Single_copy_S", "S_pct"),
        ("Duplicated_D", "D_pct"),
        ("Fragmented_F", "F_pct"),
        ("Missing_M", "M_pct"),
        ("Internal_stop_codons", "Internal_stop_codons_pct"),
    ]:
        num = pd.to_numeric(df[count_col], errors="coerce")
        df[pct_col] = (num / denom * 100).round(1)

    return df


def main():
    ap = argparse.ArgumentParser(
        description="Summarize BUSCO *-busco.log files using counts only (ignore summary line)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("-i", "--input-dir", required=True, help="Folder with BUSCO logs")
    ap.add_argument("-p", "--pattern", default="*-busco.log", help="Glob pattern")
    ap.add_argument("-o", "--output", default="busco_summary.tsv", help="Output TSV path")
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.input_dir, args.pattern)), key=natural_sort_key)
    if not paths:
        raise SystemExit(f"No files matched: {os.path.join(args.input_dir, args.pattern)}")

    records = [parse_busco_log(p) for p in paths]
    df = pd.DataFrame.from_records(records)

    # Compute percentages from counts (ignoring any summary line)
    df = compute_percents(df)

    # Optional sanity checks (kept off by default; uncomment to debug)
    # ok_complete = df["Complete_C"] == (df["Single_copy_S"].fillna(0) + df["Duplicated_D"].fillna(0))
    # ok_total = df["Total_n"] == (df["Complete_C"].fillna(0) + df["Fragmented_F"].fillna(0) + df["Missing_M"].fillna(0))
    # if not ok_complete.all() or not ok_total.all():
    #     print("WARNING: Some rows fail BUSCO consistency checks", file=sys.stderr)

    # Order columns nicely
    cols: List[str] = [
        "genome",
        # counts
        "Complete_C", "Single_copy_S", "Duplicated_D",
        "Fragmented_F", "Missing_M",
        "Internal_stop_codons",
        "Total_n",
        # percents
        "C_pct", "S_pct", "D_pct", "F_pct", "M_pct",
        "Internal_stop_codons_pct",
    ]
    df = df.reindex(columns=cols)

    df.to_csv(args.output, sep="\t", index=False, na_rep="")
    print(f"Wrote: {args.output}  (rows={len(df)}, cols={df.shape[1]})")


if __name__ == "__main__":
    main()
