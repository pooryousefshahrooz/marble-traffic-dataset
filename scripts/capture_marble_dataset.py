#!/usr/bin/env python3
"""Run real MARBLE tasks across all 4 jsonl-based categories (research,
database, coding, bargaining) against local Ollama through a TLS proxy, and
capture the real, encrypted agent<->LLM traffic with a single continuous
tcpdump -- sliced per task afterward using each task's precisely recorded
[start, end] wall-clock window (same approach as agent-to-agent's
generate_full_dataset.py).

Runs strictly sequentially: MARBLE writes to fixed relative paths
(marble/logs/app.log, marble/result/<category>_output.jsonl) and the
database category manages fixed-named Docker containers, so concurrent runs
would corrupt each other's state. This trades speed for correctness.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from scapy.all import PcapReader, wrpcap  # type: ignore

ROOT = Path(__file__).resolve().parent.parent
MARBLE_DIR = ROOT / "marble"
MULTIAGENTBENCH_DIR = ROOT / "multiagentbench"

CATEGORIES = ("research", "database", "coding", "bargaining")


def config_folder(category: str, topology: str) -> str:
    # "graph" configs were generated first, before topology was a variable,
    # into output_yaml_<category>_local; star/tree/chain went into
    # output_yaml_<category>_<topology>. Both naming schemes are kept so the
    # original graph batch doesn't need regenerating.
    return f"output_yaml_{category}_local" if topology == "graph" else f"output_yaml_{category}_{topology}"


# Each coordinate() method logs its own distinct completion message --
# checking only the graph one silently marked every star/tree/chain task as
# FAILED (and discarded its capture) even when the run genuinely succeeded.
COMPLETION_MARKERS = {
    "graph": "Graph-based coordination simulation completed.",
    "star": "Engine simulation loop completed.",
    "tree": "Tree-based coordination simulation completed.",
    "chain": "Chain-based coordination simulation completed.",
}


# database tasks pay for a full Docker/Postgres reinit (fresh initdb every
# task, not a reused container) plus a synthetic large-data load before the
# agent task even starts -- 300s isn't enough headroom for that on top of
# the actual multi-agent run, and most database tasks were being killed by
# the timeout before ever completing (confirmed: 9 task cycles in 45 min
# with zero successful results written -- consistent with near-every task
# hitting timeout, not with real completions).
TASK_TIMEOUT = {"database": 900}
DEFAULT_TIMEOUT = 300


def run_task(category: str, topology: str, task_id: int, python: str, env: dict, agent_call_log_dir: Path) -> dict:
    config_path = MULTIAGENTBENCH_DIR / config_folder(category, topology) / f"task_{task_id}.yaml"
    t_start = time.time()
    record = {"category": category, "topology": topology, "task_id": task_id, "t_start": t_start, "t_end": None, "ok": False, "info": "", "agent_calls": []}
    # Per-task sidecar log: every model_prompting() call inside this task's
    # subprocess appends (agent_id, call_start, call_end) here (see
    # marble/llms/model_prompting.py's MARBLE_AGENT_CALL_LOG handling), so
    # a task's aggregated pcap can later be sub-sliced by which agent(s)
    # were talking during a given window.
    call_log_path = agent_call_log_dir / f"{category}_{task_id}.jsonl"
    call_log_path.unlink(missing_ok=True)
    env = {**env, "MARBLE_AGENT_CALL_LOG": str(call_log_path)}
    try:
        result = subprocess.run(
            [python, "main.py", "--config_path", str(config_path)],
            cwd=str(MARBLE_DIR), env=env, capture_output=True, text=True,
            timeout=TASK_TIMEOUT.get(category, DEFAULT_TIMEOUT),
        )
        record["t_end"] = time.time()
        record["ok"] = COMPLETION_MARKERS[topology] in result.stdout + result.stderr
        if not record["ok"]:
            record["info"] = (result.stdout + result.stderr)[-500:]
    except subprocess.TimeoutExpired:
        record["t_end"] = time.time()
        record["info"] = "timeout"
    if call_log_path.exists():
        with call_log_path.open() as f:
            record["agent_calls"] = [json.loads(line) for line in f if line.strip()]
        call_log_path.unlink()
    return record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reps", type=int, default=5, help="task IDs start-rep..reps per category")
    parser.add_argument("--start-rep", type=int, default=1, help="first task_id to run (use >1 to extend a prior batch without re-running completed task_ids)")
    parser.add_argument("--categories", nargs="*", default=list(CATEGORIES))
    parser.add_argument("--topology", choices=["star", "tree", "chain", "graph"], default="graph")
    parser.add_argument("--proxy-port", type=int, default=11443)
    parser.add_argument("--iface", default=("lo0" if sys.platform == "darwin" else "lo"),
                         help="loopback interface tcpdump listens on (lo0 on macOS, lo on Linux)")
    parser.add_argument("--out-root", default=str(ROOT / "captures_marble_real"))
    parser.add_argument("--repetition-id", type=int, default=0,
                         help="which re-run of this exact task_id/category/topology set this is "
                              "(0 = first run; increment for later stochastic-variance re-runs of "
                              "the *same* task content, as distinct from task_id which selects "
                              "*which* of the sampled tasks within a category)")
    args = parser.parse_args()
    out_root = Path(args.out_root)
    out_root.mkdir(parents=True, exist_ok=True)
    raw_pcap = out_root / "continuous_raw.pcap"
    agent_call_log_dir = out_root / "agent_calls_tmp"
    agent_call_log_dir.mkdir(exist_ok=True)

    python = sys.executable
    env = os.environ.copy()
    env["MARBLE_OLLAMA_PROXY_URL"] = f"https://127.0.0.1:{args.proxy_port}"
    (MARBLE_DIR / "logs").mkdir(exist_ok=True)
    (MARBLE_DIR / "result").mkdir(exist_ok=True)

    print(f"starting TLS proxy on :{args.proxy_port} and continuous tcpdump...")
    proxy = subprocess.Popen(
        [python, str(ROOT / "scripts" / "tls_ollama_proxy.py"), "--listen-port", str(args.proxy_port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1.0)
    if proxy.poll() is not None:
        raise RuntimeError(
            f"TLS proxy exited immediately (code {proxy.returncode}) -- port {args.proxy_port} "
            f"is likely already in use by a leftover process from a previous run. "
            f"Check with: lsof -i :{args.proxy_port}"
        )
    tcpdump = subprocess.Popen(
        ["sudo", "-n", "tcpdump", "-i", args.iface, "-w", str(raw_pcap), f"tcp port {args.proxy_port}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1.0)

    records = []
    try:
        for category in args.categories:
            for task_id in range(args.start_rep, args.reps + 1):
                if tcpdump.poll() is not None:
                    print(f"ABORTING: tcpdump (pid {tcpdump.pid}) died unexpectedly "
                          f"(exit code {tcpdump.returncode}) -- no point running more "
                          f"tasks with no capture. {len(records)} tasks already ran this batch.")
                    break
                pcap_size_before = raw_pcap.stat().st_size if raw_pcap.exists() else 0
                print(f"running {category}/{args.topology}/task_{task_id}...")
                rec = run_task(category, args.topology, task_id, python, env, agent_call_log_dir)
                records.append(rec)
                status = "OK" if rec["ok"] else f"FAILED: {rec['info'][:150]}"
                print(f"  {status} ({rec['t_end']-rec['t_start']:.1f}s)")
                # A successful task always makes at least one real LLM call over
                # the proxied port -- if tcpdump is alive but has stopped actually
                # writing packets (hung, not exited -- process.poll() misses this),
                # a completed task with zero new capture bytes is the tell.
                if rec["ok"]:
                    pcap_size_after = raw_pcap.stat().st_size if raw_pcap.exists() else 0
                    if pcap_size_after <= pcap_size_before:
                        print(f"ABORTING: tcpdump (pid {tcpdump.pid}) is alive but produced "
                              f"zero new capture bytes during a successful task -- capture has "
                              f"stalled. {len(records)} tasks already ran this batch.")
                        break
            else:
                continue
            break
    finally:
        proxy.terminate()
        subprocess.run(["sudo", "-n", "kill", str(tcpdump.pid)], capture_output=True)
        time.sleep(1.0)
        print(f"tcpdump pid (clean up manually if still running): {tcpdump.pid}")

    ok_records = [r for r in records if r["ok"]]
    print(f"\n{len(ok_records)}/{len(records)} tasks completed successfully")

    print("slicing per-task pcaps from continuous capture...")
    llm_dir = out_root / "captures_llm"
    llm_dir.mkdir(exist_ok=True)
    buckets: dict[int, list] = {i: [] for i in range(len(ok_records))}
    if raw_pcap.exists():
        with PcapReader(str(raw_pcap)) as reader:
            for pkt in reader:
                ts = float(pkt.time)
                for i, rec in enumerate(ok_records):
                    if rec["t_start"] - 1.0 <= ts <= rec["t_end"] + 1.0:
                        buckets[i].append(pkt)
                        break

    index_path = out_root / "dataset_index.csv"
    with index_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["category", "task_id", "repetition_id", "model", "topology", "llm_pcap", "llm_packets", "agent_calls_json"])
        writer.writeheader()
        for i, rec in enumerate(ok_records):
            base_name = f"{rec['category']}_{rec['topology']}_ollama-llama3.2-3b_{rec['task_id']:03d}_rep{args.repetition_id}"
            out_path = llm_dir / f"{base_name}.pcap"
            if buckets[i]:
                wrpcap(str(out_path), buckets[i])
            # Per-agent call-timing sidecar (agent_id, call_start, call_end
            # for every LLM call in this task) -- lets analysis later
            # extract traffic for any chosen subset of agents from this same
            # pcap, without needing to re-capture per subset.
            calls_path = llm_dir / f"{base_name}.agent_calls.json"
            calls_path.write_text(json.dumps(rec["agent_calls"]))
            writer.writerow({
                "category": rec["category"], "task_id": rec["task_id"], "repetition_id": args.repetition_id,
                "model": "llama3.2:3b", "topology": rec["topology"],
                "llm_pcap": str(out_path) if buckets[i] else "", "llm_packets": len(buckets[i]),
                "agent_calls_json": str(calls_path),
            })
    print(f"wrote index: {index_path}")


if __name__ == "__main__":
    main()
