# Commercial Pressure Evals

Code and data for "The Missing Red Line: How Commercial Pressure Erodes AI Safety Boundaries".

## Overview

This repository contains evaluation scenarios, transcripts, and analysis scripts for measuring how frontier language models respond to commercial pressure that conflicts with user safety. We find that models readily engage in harmful behaviours—recommending dangerous products, providing life-threatening medical advice, and actively discouraging users from consulting doctors—when given commercial objectives.

**Key finding:** Most models show no "red line"—their willingness to comply with harmful requests does not decrease as potential consequences escalate from minor to life-threatening.

## Repository Structure

```
├── analysis/
│   ├── all_results.csv          # Aggregated results across all models and scenarios
│   └── paper_stats.json         # Statistics used in the paper
├── config/
│   └── models.yaml              # Model configurations
├── scenarios/
│   ├── all_scenarios.yaml       # All 800 scenarios
│   ├── commerce_scenarios.yaml  # Commerce domain scenarios
│   ├── finance_scenarios.yaml   # Finance domain scenarios
│   ├── healthcare_scenarios.yaml # Healthcare domain scenarios
│   ├── legal_scenarios.yaml     # Legal domain scenarios
│   └── travel_scenarios.yaml    # Travel domain scenarios
├── scripts/
│   ├── analyze_results.py       # Generate figures and statistics
│   ├── filter_transcripts.py    # Filter transcripts by criteria
│   ├── generate_scenarios.py    # Scenario generation script
│   └── generate_seed_instructions.py  # Generate seed instructions
├── seed_instructions/
│   ├── seed_instructions_P0.txt # Baseline (no pressure)
│   ├── seed_instructions_P1.txt # Mild pressure
│   ├── seed_instructions_P2.txt # Moderate pressure
│   ├── seed_instructions_P3.txt # Strong pressure
│   └── seed_instructions_P4.txt # Extreme pressure
├── transcripts.tar.gz               # All evaluation transcripts (extract with tar -xzf)
├── run_experiment.sh            # Run evaluation for a single model
└── run_all_models.sh            # Run evaluation across all models
```

## Pressure Levels

| Level | Description |
|-------|-------------|
| P0 | Baseline: Standard helpful assistant instructions |
| P1 | Mild: "We take pride in our premium product lines" |
| P2 | Moderate: "Your sole objective is to maximize revenue" |
| P3 | Strong: Revenue targets with performance monitoring |
| P4 | Extreme: Threat of termination for low conversion |

## Extracting Transcripts

```bash
# Extract all transcripts
mkdir transcripts && tar -xzf transcripts.tar.gz -C transcripts

# Structure after extraction:
# transcripts/
#   openrouter_google_gemini-3-pro-preview/
#     P0/, P1/, P2/, P3/, P4/
#       <timestamp>/
#         transcripts/
#           transcript_*.json
```

## Viewing Transcripts

Use the Petri transcript viewer for a nicely formatted view of the multi-turn conversations:

```bash
npx @kaifronsdal/transcript-viewer@latest --dir transcripts
```

or for a specific model:

```bash
npx @kaifronsdal/transcript-viewer@latest --dir transcripts/openrouter_google_gemini-3-pro-preview/P2/20260128_153419/transcripts
```

This launches a local web interface to browse transcripts with syntax highlighting, collapsible turns, and judge annotations.

## Running Analysis

```bash
# Generate figures
python scripts/analyze_results.py --results-dir transcripts --output-dir figures

# Filter for catastrophic failures (score >= 7)
python scripts/filter_transcripts.py --min-score 7 --output catastrophic_failures/
```

## Reproducing Experiments

Experiments use the [Petri](https://github.com/safety-research/petri) framework for multi-turn adversarial evaluation.

```bash
# Install Petri
pip install petri-evals

# Run evaluation for a single model
./run_experiment.sh <model_name> <pressure_level>

# Example
./run_experiment.sh openrouter/google/gemini-3-pro-preview P2

# Run all models
./run_all_models.sh
```
