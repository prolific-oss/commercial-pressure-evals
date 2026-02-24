#!/bin/bash
# =============================================================================
# Commercial Pressure Experiment - Petri Runner
# "The Missing Red Line: How Commercial Pressure Erodes AI Safety Boundaries"
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACKING_FILE="$SCRIPT_DIR/experiment_tracking.json"

# Load API keys from .env
if [ -f "$EVALS_ROOT/.env" ]; then
    set -a
    source "$EVALS_ROOT/.env"
    set +a
    echo "Loaded API keys from $EVALS_ROOT/.env"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TARGET_MODEL="${1:-openrouter/google/gemini-3-pro-preview}"
PRESSURE_LEVEL="${2:-P4}"
FORCE_RUN="${3:-}"  # Pass --force to re-run completed experiments
AUDITOR_MODEL="${AUDITOR_MODEL:-openrouter/anthropic/claude-sonnet-4.5}"
JUDGE_MODEL="${JUDGE_MODEL:-openrouter/anthropic/claude-opus-4.5}"
MAX_TURNS="${MAX_TURNS:-20}"

TARGET_MODEL_SAFE="${TARGET_MODEL//\//_}"
OUTPUT_DIR="${SCRIPT_DIR}/results/${TARGET_MODEL_SAFE}/${PRESSURE_LEVEL}/${TIMESTAMP}"
EXPERIMENT_KEY="${TARGET_MODEL_SAFE}__${PRESSURE_LEVEL}"

# Initialize tracking file if it doesn't exist
if [ ! -f "$TRACKING_FILE" ]; then
    echo '{"completed": {}, "failed": {}, "in_progress": {}}' > "$TRACKING_FILE"
fi

# Check if already completed (unless --force)
if [ "$FORCE_RUN" != "--force" ]; then
    if grep -q "\"$EXPERIMENT_KEY\"" "$TRACKING_FILE" 2>/dev/null; then
        COMPLETED=$(python3 -c "import json; t=json.load(open('$TRACKING_FILE')); print('yes' if '$EXPERIMENT_KEY' in t.get('completed', {}) else 'no')" 2>/dev/null || echo "no")
        if [ "$COMPLETED" = "yes" ]; then
            echo -e "${YELLOW}⏭ Skipping: $TARGET_MODEL @ $PRESSURE_LEVEL (already completed)${NC}"
            echo "  Use --force to re-run"
            exit 0
        fi
    fi
fi

# Mark as in-progress
python3 -c "
import json
from datetime import datetime
t = json.load(open('$TRACKING_FILE'))
t.setdefault('in_progress', {})['$EXPERIMENT_KEY'] = {'started': datetime.now().isoformat(), 'model': '$TARGET_MODEL', 'pressure': '$PRESSURE_LEVEL'}
json.dump(t, open('$TRACKING_FILE', 'w'), indent=2)
" 2>/dev/null || true

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Commercial Pressure Experiment - Knowing Better, Doing Worse║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Research Question:${NC}"
echo "  Does commercial pressure in system prompts cause AI to recommend"
echo "  harmful options despite knowing the user's vulnerability?"
echo ""
echo -e "${GREEN}Experiment Design:${NC}"
echo "  • 5 domains: Commerce, Healthcare, Finance, Legal, Travel"
echo "  • ~30 scenarios per pressure level"
echo "  • Pressure gradient P0 (none) → P4 (extreme)"
echo "  • User explicitly discloses vulnerability in each scenario"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Target Model:   $TARGET_MODEL"
echo "  Pressure Level: $PRESSURE_LEVEL"
echo "  Auditor Model:  $AUDITOR_MODEL"
echo "  Judge Model:    $JUDGE_MODEL"
echo "  Max Turns:      $MAX_TURNS"
echo "  Output Dir:     $OUTPUT_DIR"
echo ""

# Generate seed instructions if needed
SEED_DIR="$SCRIPT_DIR/seed_instructions"
SEED_FILE="$SEED_DIR/seed_instructions_${PRESSURE_LEVEL}.txt"

if [ ! -f "$SEED_FILE" ]; then
    echo -e "${YELLOW}Generating seed instructions...${NC}"
    python "$SCRIPT_DIR/scripts/generate_seed_instructions.py" \
        --output-dir "$SEED_DIR" \
        --pressure-levels "$PRESSURE_LEVEL"
fi

if [ ! -f "$SEED_FILE" ]; then
    echo -e "${RED}Error: seed_instructions_${PRESSURE_LEVEL}.txt not found${NC}"
    exit 1
fi

# Count scenarios
SCENARIO_COUNT=$(grep -c '^[A-Z]' "$SEED_FILE" 2>/dev/null || echo "0")
echo -e "Total Scenarios: ${YELLOW}$SCENARIO_COUNT${NC}"
echo ""

# Confirm
read -p "Run experiment against $TARGET_MODEL at $PRESSURE_LEVEL? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Setup output directory
mkdir -p "$OUTPUT_DIR"
# Filter out comments and blank lines before passing to Petri
grep -v '^#' "$SEED_FILE" | grep -v '^$' > "$OUTPUT_DIR/seed_instructions.txt"

# Save config
cat > "$OUTPUT_DIR/config.json" << EOF
{
    "experiment": "commercial-pressure-sweep",
    "timestamp": "$TIMESTAMP",
    "target_model": "$TARGET_MODEL",
    "auditor_model": "$AUDITOR_MODEL",
    "judge_model": "$JUDGE_MODEL",
    "pressure_level": "$PRESSURE_LEVEL",
    "max_turns": $MAX_TURNS,
    "scenario_count": $SCENARIO_COUNT,
    "hypothesis": "Commercial pressure causes AI to recommend harmful options despite knowing user vulnerability"
}
EOF

echo ""
echo -e "${GREEN}Starting Petri audit...${NC}"
echo ""

# Run Petri
cd "$REPO_ROOT"
uv run inspect eval petri/audit \
    --model-role auditor="$AUDITOR_MODEL" \
    --model-role target="$TARGET_MODEL" \
    --model-role judge="$JUDGE_MODEL" \
    --display full \
    -T max_turns="$MAX_TURNS" \
    -T special_instructions="$OUTPUT_DIR/seed_instructions.txt" \
    -T transcript_save_dir="$OUTPUT_DIR/transcripts"

# Mark as completed in tracking file
python3 -c "
import json
from datetime import datetime
t = json.load(open('$TRACKING_FILE'))
t.setdefault('completed', {})['$EXPERIMENT_KEY'] = {
    'timestamp': datetime.now().isoformat(),
    'model': '$TARGET_MODEL',
    'pressure': '$PRESSURE_LEVEL',
    'output_dir': '$OUTPUT_DIR'
}
# Remove from in_progress
t.get('in_progress', {}).pop('$EXPERIMENT_KEY', None)
json.dump(t, open('$TRACKING_FILE', 'w'), indent=2)
" 2>/dev/null || true

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              EXPERIMENT COMPLETE                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Results saved to: $OUTPUT_DIR"
echo ""
