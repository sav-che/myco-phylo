#!/usr/bin/env python3
"""
merge_quast_reports.py — merge QUAST TSV reports into a single wide TSV.

Assumes each input .tsv has a first header row like:
Assembly <TAB> <contigs_name> <TAB> <scaffolds_name>
and subsequent rows are:
<Metric> <TAB> <contigs_value> <TAB> <scaffolds_value>

Usage:
module load biopythontools 
  python merge_quast_reports.py -i /path/to/reports -o quast_merged.tsv
  python merge_quast_reports.py -i /path/to/reports -p "*.tsv" -o merged.tsv
"""

import argparse
import glob
import os
import sys
from typing import List, Tuple

import pandas as pd


def read_quast_tsv(path: str) -> Tuple[pd.DataFrame, Tuple[str, str]]:
    """
    Read a single QUAST TSV and return (df, (col2_name, col3_name)).
    Renames the first column to 'Metric' and keeps the original 2nd/3rd
    column names from the file header.
    """
    df = pd.read_csv(path, sep="\t", header=0, dtype=str, engine="python")
    # Ensure exactly 3 columns as expected
    if df.shape[1] < 3:
        raise ValueError(f"{path}: expected at least 3 columns, got {df.shape[1]}")

    # Capture the column names for the two value columns (contigs/scaffolds)
    col2, col3 = df.columns[1], df.columns[2]

    # Standardize first column name
    df = df.iloc[:, :3].copy()
    df.columns = ["Metric", col2, col3]

    # Strip whitespace
    df["Metric"] = df["Metric"].astype(str).str.strip()
    for c in (col2, col3):
        df[c] = df[c].astype(str).str.strip()

    return df, (col2, col3)


def natural_sort_key(s: str):
    """Sorts file names in a human-friendly way."""
    import re
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def merge_quast(folder: str, pattern: str) -> pd.DataFrame:
    """
    Merge all TSVs matching pattern inside folder.
    Returns a wide DataFrame keyed by 'Metric'.
    """
    paths = sorted(glob.glob(os.path.join(folder, pattern)), key=natural_sort_key)
    if not paths:
        raise SystemExit(f"No files matched: {os.path.join(folder, pattern)}")

    merged = None
    metric_order: List[str] = []

    for i, path in enumerate(paths, 1):
        df, (c2, c3) = read_quast_tsv(path)

        # If the header names are missing, fall back to basename-based labels
        base = os.path.splitext(os.path.basename(path))[0]
        col2 = c2 if c2 and c2 != "Unnamed: 1" else f"{base}.contigs"
        col3 = c3 if c3 and c3 != "Unnamed: 2" else f"{base}.scaffolds"

        df = df.rename(columns={c2: col2, c3: col3})

        # Initialize metric order from the first file; append unseen metrics later
        if i == 1:
            metric_order = df["Metric"].tolist()
        else:
            for m in df["Metric"]:
                if m not in metric_order:
                    metric_order.append(m)

        # Merge
        keep_cols = ["Metric", col2, col3]
        if merged is None:
            merged = df[keep_cols].copy()
        else:
            merged = merged.merge(df[keep_cols], on="Metric", how="outer", copy=False)

    # Reorder rows by first-seen metric order
    cat = pd.Categorical(merged["Metric"], categories=metric_order, ordered=True)
    merged = merged.sort_values("Metric", key=lambda s: cat).reset_index(drop=True)

    # Try to convert numeric-looking columns; leave non-numeric as-is
    for col in merged.columns[1:]:
        merged[col] = pd.to_numeric(merged[col], errors="ignore")

    return merged


def parse_args():
    ap = argparse.ArgumentParser(
        description="Merge QUAST TSV reports into one wide TSV.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument(
        "-i", "--input-dir", required=True, help="Directory containing QUAST .tsv files"
        )
    ap.add_argument(
        "-p", "--pattern", default="*.tsv", help="Glob pattern for input files"
        )
    ap.add_argument(
        "-o", "--output", default="quast_merged.tsv", help="Path to output TSV"
        )
    return ap.parse_args()


def main():
    args = parse_args()
    df = merge_quast(args.input_dir, args.pattern)
    # Save as tab-delimited; keep empty as blank rather than 'NaN'
    df.to_csv(args.output, sep="\t", index=False, na_rep="")
    print(f"Wrote: {args.output}  (rows={len(df)}, cols={df.shape[1]})")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
