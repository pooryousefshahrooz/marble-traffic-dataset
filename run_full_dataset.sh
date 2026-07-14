#!/usr/bin/env bash
# Runs the full real-MARBLE encrypted-traffic dataset collection: all 4
# coordination topologies (graph/star/tree/chain) x all 4 task categories
# (bargaining/research/coding/database) x 15 sampled tasks each = up to 240
# real MARBLE runs, each with its own genuinely TLS-encrypted, tcpdump-
# captured agent<->LLM traffic sliced into a per-task .pcap.
#
# Run this after ./setup.sh. Takes many hours -- chain topology in
# particular can run 20+ sequential LLM hops per task. Safe to Ctrl-C and
# resume: pass --start-rep to a given topology to skip already-completed
# task_ids (see scripts/capture_marble_dataset.py --help).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
source .venv/bin/activate

CATEGORIES="bargaining research coding database"
REPS=15
OUT_BASE="captures_marble_full"

for TOPOLOGY in graph star tree chain; do
    OUT_DIR="${OUT_BASE}_${TOPOLOGY}"
    echo ""
    echo "=================================================="
    echo " topology: $TOPOLOGY  ->  $OUT_DIR"
    echo "=================================================="
    python3 scripts/capture_marble_dataset.py \
        --topology "$TOPOLOGY" \
        --categories $CATEGORIES \
        --reps "$REPS" \
        --out-root "$OUT_DIR"
done

echo ""
echo "=== merging all topology indices into one dataset_index.csv ==="
python3 - <<'PYEOF'
import csv, glob

rows = []
for path in sorted(glob.glob("captures_marble_full_*/dataset_index.csv")):
    rows.extend(csv.DictReader(open(path)))

fieldnames = ["category", "task_id", "repetition_id", "model", "topology", "llm_pcap", "llm_packets"]
with open("dataset_index_merged.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in rows:
        r.setdefault("repetition_id", 0)
        w.writerow(r)

print(f"wrote dataset_index_merged.csv with {len(rows)} rows")
PYEOF

echo ""
echo "=== done. dataset_index_merged.csv has the full merged index. ==="
