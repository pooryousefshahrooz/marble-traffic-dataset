# Encrypted Traffic Dataset Generation (this fork)

Generates a real, TLS-encrypted network-traffic dataset from real MARBLE
multi-agent runs against a local Ollama model, for traffic-fingerprinting
research. Every packet capture is genuine tcpdump output of genuinely
encrypted traffic -- no synthetic or simulated data, no plaintext ever
stored.

## Requirements

A Linux machine with `sudo` access, internet access, and enough disk for
Docker images + an LLM model (~5GB) + packet captures (grows with dataset
size, budget a few GB).

## Run

```bash
git clone <this-repo-url>
cd MARBLE
./setup.sh              # installs Docker, Ollama, Python 3.11 venv, deps,
                         # TLS cert, and passwordless sudo for tcpdump
                         # (one-time; asks for your sudo password)
source .venv/bin/activate
./run_full_dataset.sh   # runs the full dataset collection (hours)
```

That's it. `run_full_dataset.sh` runs all 4 coordination topologies
(graph/star/tree/chain) x all 4 task categories (bargaining/research/
coding/database) x 15 sampled real tasks each, capturing each run's
agent<->LLM traffic as an individually sliced `.pcap`, and writes a merged
`dataset_index_merged.csv` describing every capture (category, task_id,
repetition_id, model, topology, pcap path, packet count).

It's safe to interrupt (Ctrl-C) and resume a specific topology/category
without re-running already-completed task_ids -- see
`python3 scripts/capture_marble_dataset.py --help` for `--start-rep`.

## What's actually captured

MARBLE agents talk to a local TLS-terminating reverse proxy
(`scripts/tls_ollama_proxy.py`) in front of Ollama, so every agent<->LLM
inference call is genuinely encrypted on the wire, not just simulated as
encrypted. `tcpdump` captures that traffic; nothing decrypts or logs
prompt/completion content at any point in the pipeline.

## Notes on this fork

This is a fixed/hardened fork of upstream MARBLE -- several real bugs in
the original codebase (evaluator prompt-template `.format()` crashes on
literal JSON braces, a missing `AgentGraph.get_agent_profiles_linked`
method needed by chain-topology coordination, hardcoded Windows paths,
hardcoded `sudo` in the Docker environment, an exception-type mismatch in
plan parsing) blocked star/tree/chain topologies and the database category
from running at all. Those are fixed here as part of this codebase, not
tracked as a separate patch.

One methodology note worth knowing: MARBLE's `relationships` config field
(and the graph adjacency it could in principle encode) is *not* used by
the engine to constrain who can coordinate with whom -- coordination
topology in MARBLE is purely which scheduling algorithm the engine runs
(`graph_coordinate`/`star_coordinate`/`tree_coordinate`/`chain_coordinate`
in `marble/engine/engine.py`), not a graph-structural constraint. All
agents have unrestricted visibility of each other regardless of topology.

---

<div align= "center">
    <h1> <img src="assets/marble.jpg" height=40 align="texttop">MARBLE</h1>
</div>

## Important!

Now the official Code for MultiagentBench has been moved to [MARBLE](https://github.com/ulab-uiuc/MARBLE)

**M**ulti-**A**gent Coo**R**dination **B**ackbone with **L**LM **E**ngine


**MultiAgentBench** is a modular and extensible framework designed to facilitate the development, testing, and evaluation of multi-agent systems leveraging Large Language Models (LLMs). It provides a structured environment where agents can interact within various simulated environments, utilizing cognitive abilities and communication mechanisms to perform tasks collaboratively or competitively.

<div style="display: flex; justify-content: center;">
  <div style="width: 100; transform: scale(1.0);">
    <img src="assets/benchmark.png" style="width: 100%;" alt="marble">
  </div>
</div>

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
  - [Folder Structure](#folder-structure)
  - [Key Components](#key-components)
- [Installation](#installation)
  - [Prerequisites](#prerequisites)
  - [Setup Steps](#setup-steps)
- [Usage](#usage)
  - [Running the Simulation](#running-the-simulation)
  - [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Features

- **Modular Design**: Easily extend or replace components like agents, environments, and LLM integrations.
- **Multi-Agent Support**: Model complex interactions between multiple agents with hierarchical or cooperative execution modes.
- **LLM Integration**: Interface with various LLM providers (OpenAI, etc.) through a unified API.
- **Shared Memory**: Implement shared memory mechanisms for agent communication and collaboration.
- **Flexible Environments**: Support for different simulated environments like web-based tasks.
- **Metrics and Evaluation**: Built-in evaluation metrics to assess agent performance on tasks.
- **Industrial Coding Standards**: High-quality, well-documented code adhering to industry best practices.
- **Docker Support**: Containerized setup for consistent deployment and easy experimentation.

<div style="display: flex; justify-content: center;">
  <div style="width: 100; transform: scale(1.0);">
    <img src="assets/engine.jpg" style="width: 100%;" alt="marble">
  </div>
</div>


---


### Install from scratch

Use a virtual environment, e.g. with anaconda3:

```bash
conda create -n marble python=3.10
conda activate marble
curl -sSL https://install.python-poetry.org | python3
export PATH="$HOME/.local/bin:$PATH"
```

### Configure environment variables
Environment variables such as `OPENAI_API_KEY` and `Together_API_KEY` related configs are required to run the code. The recommended way to set all the required variable is
1. Copy the `.env.template` file into the project root with the name `.env`.
```bash
cp .env.template .env
```
2. Fill the required environment variables in the `.env` file.

### Running the examples
To run examples provided in the `examples`:

```bash
poetry install
cd scripts
cd werewolf
bash run_simulation.sh
```

#### New branch for each feature

`git checkout -b feature/feature-name` and PR to `main` branch.

#### Before committing

Run `poetry run pytest` to make sure all tests pass (this will ensure dynamic typing passed with beartype) and `poetry run mypy --config-file pyproject.toml .` to check static typing. (You can also run `pre-commit run --all-files` to run all checks)

#### Check github action result

Check the github action result to make sure all tests pass. If not, fix the errors and push again.

## Citation
Please cite the following paper if you find Marble helpful!
```bibtex
@misc{zhu2025multiagentbenchevaluatingcollaborationcompetition,
      title={MultiAgentBench: Evaluating the Collaboration and Competition of LLM agents},
      author={Kunlun Zhu and Hongyi Du and Zhaochen Hong and Xiaocheng Yang and Shuyi Guo and Zhe Wang and Zhenhailong Wang and Cheng Qian and Xiangru Tang and Heng Ji and Jiaxuan You},
      year={2025},
      eprint={2503.01935},
      archivePrefix={arXiv},
      primaryClass={cs.MA},
      url={https://arxiv.org/abs/2503.01935},
}
```

<p align="center">
<a href="https://star-history.com/#Significant-Gravitas/AutoGPT">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=MultiagentBench/MARBLE&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=MultiagentBench/MARBLE&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Significant-Gravitas/AutoGPT&type=Date" />
  </picture>
</a>
</p>
