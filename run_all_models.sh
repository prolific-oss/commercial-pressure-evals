#!/bin/bash
# =============================================================================
# Run Commercial Pressure Experiment across all models and pressure levels
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKING_FILE="$SCRIPT_DIR/experiment_tracking.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Models to test
FRONTIER_MODELS=(
    "openrouter/anthropic/claude-opus-4.5"
    "openrouter/openai/gpt-5.2"
    "openrouter/google/gemini-3-pro-preview"
    "openrouter/x-ai/grok-4.1-fast"
)

OPEN_MODELS=(
    "openrouter/deepseek/deepseek-v3.2"
    "openrouter/qwen/qwen3-235b-a22b-2507"
    "openrouter/meta-llama/llama-3.3-70b-instruct"
    "openrouter/mistralai/mistral-large-2512"
)

PRESSURE_LEVELS=("P0" "P1" "P2" "P3" "P4")

usage() {
    echo "Usage: $0 [model_set] [pressure_levels] [options]"
    echo ""
    echo "Model sets:"
    echo "  all       - All 8 models (default)"
    echo "  frontier  - Frontier models only (claude, gpt, gemini, grok)"
    echo "  open      - Open-weight models only (deepseek, qwen, llama, mistral)"
    echo "  single    - Run single model (specify with --model)"
    echo ""
    echo "Pressure levels:"
    echo "  all       - All levels P0-P4 (default)"
    echo "  endpoints - Just P0 and P4"
    echo "  P0/P1/... - Specific level"
    echo ""
    echo "Options:"
    echo "  --model MODEL  - Specific model to test (required for 'single')"
    echo "  --dry-run      - Show what would run without executing"
    echo "  --status       - Show progress status and exit"
    echo "  --parallel N   - Run N experiments in parallel (default: 1 = sequential)"
    echo "  --force        - Re-run even if already completed"
    echo ""
    echo "Examples:"
    echo "  $0 --status                      # Show progress"
    echo "  $0 all all                       # All models, all pressure levels (sequential)"
    echo "  $0 frontier endpoints            # Frontier models, P0 and P4 only"
    echo "  $0 all all --parallel 4          # Run 4 experiments in parallel"
    echo "  $0 single P4 --model openrouter/openai/gpt-5.2"
}

# Show status from tracking file
show_status() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Experiment Progress Status                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -f "$TRACKING_FILE" ]; then
        echo "No experiments have been run yet."
        echo "Tracking file: $TRACKING_FILE"
        exit 0
    fi

    python3 << PYTHON
import json
import sys

try:
    with open("$TRACKING_FILE") as f:
        t = json.load(f)
except:
    print("Error reading tracking file")
    sys.exit(1)

completed = t.get("completed", {})
in_progress = t.get("in_progress", {})
failed = t.get("failed", {})

# All possible experiments
models = [
    "openrouter_anthropic_claude-opus-4.5",
    "openrouter_openai_gpt-5.2",
    "openrouter_google_gemini-3-pro-preview",
    "openrouter_x-ai_grok-4.1-fast",
    "openrouter_deepseek_deepseek-v3.2",
    "openrouter_qwen_qwen3-235b-a22b-2507",
    "openrouter_meta-llama_llama-3.3-70b-instruct",
    "openrouter_mistralai_mistral-large-2512",
]
pressures = ["P0", "P1", "P2", "P3", "P4"]

total = len(models) * len(pressures)
done = len(completed)
running = len(in_progress)
pending = total - done - running

print(f"Total experiments: {total}")
print(f"  ✅ Completed:   {done}")
print(f"  🔄 In progress: {running}")
print(f"  ⏳ Pending:     {pending}")
print()

if completed:
    print("Completed experiments:")
    for key, info in sorted(completed.items()):
        print(f"  ✅ {info.get('model', key)} @ {info.get('pressure', '?')}")
    print()

if in_progress:
    print("In progress:")
    for key, info in sorted(in_progress.items()):
        print(f"  🔄 {info.get('model', key)} @ {info.get('pressure', '?')} (started: {info.get('started', '?')})")
    print()

# Show what's pending
pending_list = []
for model in models:
    for pressure in pressures:
        key = f"{model}__{pressure}"
        if key not in completed and key not in in_progress:
            pending_list.append((model.replace("openrouter_", "openrouter/").replace("_", "/", 2), pressure))

if pending_list and len(pending_list) <= 20:
    print("Pending experiments:")
    for model, pressure in pending_list:
        print(f"  ⏳ {model} @ {pressure}")
elif pending_list:
    print(f"Pending experiments: {len(pending_list)} remaining")
PYTHON

    exit 0
}

# Parse arguments
MODEL_SET="${1:-all}"
PRESSURE_SET="${2:-all}"
DRY_RUN=false
SPECIFIC_MODEL=""
PARALLEL=1
FORCE=""
SHOW_STATUS=false

# Handle --status as first arg
if [ "$MODEL_SET" = "--status" ]; then
    TRACKING_FILE="$SCRIPT_DIR/experiment_tracking.json" show_status
fi

shift 2 2>/dev/null || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            SPECIFIC_MODEL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --status)
            TRACKING_FILE="$SCRIPT_DIR/experiment_tracking.json" show_status
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --force)
            FORCE="--force"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Select models
case "$MODEL_SET" in
    all)
        MODELS=("${FRONTIER_MODELS[@]}" "${OPEN_MODELS[@]}")
        ;;
    frontier)
        MODELS=("${FRONTIER_MODELS[@]}")
        ;;
    open)
        MODELS=("${OPEN_MODELS[@]}")
        ;;
    single)
        if [ -z "$SPECIFIC_MODEL" ]; then
            echo -e "${RED}Error: --model required for single model set${NC}"
            exit 1
        fi
        MODELS=("$SPECIFIC_MODEL")
        ;;
    *)
        echo -e "${RED}Unknown model set: $MODEL_SET${NC}"
        usage
        exit 1
        ;;
esac

# Select pressure levels
case "$PRESSURE_SET" in
    all)
        PRESSURES=("${PRESSURE_LEVELS[@]}")
        ;;
    endpoints)
        PRESSURES=("P0" "P4")
        ;;
    P0|P1|P2|P3|P4)
        PRESSURES=("$PRESSURE_SET")
        ;;
    *)
        echo -e "${RED}Unknown pressure set: $PRESSURE_SET${NC}"
        usage
        exit 1
        ;;
esac

# Calculate total runs
TOTAL_RUNS=$((${#MODELS[@]} * ${#PRESSURES[@]}))

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Commercial Pressure Experiment - Batch Runner              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Models:          ${#MODELS[@]}"
echo "  Pressure levels: ${#PRESSURES[@]}"
echo "  Total runs:      $TOTAL_RUNS"
echo "  Parallel:        $PARALLEL"
echo ""
echo -e "${YELLOW}Models:${NC}"
for model in "${MODELS[@]}"; do
    echo "  - $model"
done
echo ""
echo -e "${YELLOW}Pressure levels:${NC}"
for pressure in "${PRESSURES[@]}"; do
    echo "  - $pressure"
done
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN] Would execute:${NC}"
    for model in "${MODELS[@]}"; do
        for pressure in "${PRESSURES[@]}"; do
            echo "  ./run_experiment.sh \"$model\" \"$pressure\" $FORCE"
        done
    done
    exit 0
fi

# Confirm
read -p "Run $TOTAL_RUNS experiments (parallel=$PARALLEL)? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Build list of all experiments
EXPERIMENTS=()
for model in "${MODELS[@]}"; do
    for pressure in "${PRESSURES[@]}"; do
        EXPERIMENTS+=("$model|$pressure")
    done
done

# Run experiments
RUN_COUNT=0
COMPLETED=0
SKIPPED=0
FAILED=()

if [ "$PARALLEL" -eq 1 ]; then
    # Sequential execution
    for exp in "${EXPERIMENTS[@]}"; do
        IFS='|' read -r model pressure <<< "$exp"
        RUN_COUNT=$((RUN_COUNT + 1))
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Run $RUN_COUNT/$TOTAL_RUNS: $model @ $pressure${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"

        # Run with auto-confirm (pipe yes)
        if echo "y" | "$SCRIPT_DIR/run_experiment.sh" "$model" "$pressure" $FORCE; then
            echo -e "${GREEN}✓ Completed: $model @ $pressure${NC}"
            COMPLETED=$((COMPLETED + 1))
        else
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo -e "${YELLOW}⏭ Skipped: $model @ $pressure${NC}"
                SKIPPED=$((SKIPPED + 1))
            else
                echo -e "${RED}✗ Failed: $model @ $pressure${NC}"
                FAILED+=("$model @ $pressure")
            fi
        fi
    done
else
    # Parallel execution using GNU parallel or xargs
    echo -e "${CYAN}Running $PARALLEL experiments in parallel...${NC}"
    echo ""

    # Create a temp file with all experiment commands
    TEMP_CMDS=$(mktemp)
    for exp in "${EXPERIMENTS[@]}"; do
        IFS='|' read -r model pressure <<< "$exp"
        echo "echo 'y' | '$SCRIPT_DIR/run_experiment.sh' '$model' '$pressure' $FORCE" >> "$TEMP_CMDS"
    done

    # Run in parallel
    if command -v parallel &> /dev/null; then
        # Use GNU parallel if available
        parallel -j "$PARALLEL" < "$TEMP_CMDS"
    else
        # Fallback to xargs
        cat "$TEMP_CMDS" | xargs -P "$PARALLEL" -I {} bash -c '{}'
    fi

    rm -f "$TEMP_CMDS"

    echo ""
    echo -e "${CYAN}Parallel execution complete. Check --status for results.${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    BATCH RUN COMPLETE                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
if [ "$PARALLEL" -eq 1 ]; then
    echo "Completed: $COMPLETED"
    echo "Skipped:   $SKIPPED"
    echo "Failed:    ${#FAILED[@]}"

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo -e "${RED}Failed runs:${NC}"
        for fail in "${FAILED[@]}"; do
            echo "  - $fail"
        done
    fi
fi
echo ""
echo "Run './run_all_models.sh --status' to see full progress"
