#!/bin/bash

###### THIS IS FOR BATCHING JOBS ON DOCKER

DO_GENERATE_DESIGN_POINTS=true
DO_BATCH_RUN=true
DO_RIVET_MERGE=true
DO_WRITE_INPUTS=true

# === Config ===
COLLISIONS="pp_200"    #"pp_7000 pp_13000"
TOTAL_POINTS=5          # Total number of design points
TOTAL_EVENTS=1000         # Total number of events across all jobs
NEVENTS=1000              # Events per job
CPU=5                   # USER sets how many CPUs to use
TARGET_EVENTS_PER_JOB=1000000

# === PATHS ===
MAIN_DIR="${WORKDIR:-/workdir}/Detroit_tune_Project"
MAIN_SCRIPT="$MAIN_DIR/Batch_Rivet/Rivet_Main.py"

# Safe random seed in 32-bit range
MAX_SEED=900000000 # Pythia’s max seed
raw_ts=$(date +%s%N)
SEED=$(( raw_ts % MAX_SEED + 1 ))

ACTUAL_JOBS=$(( (TOTAL_POINTS + BATCH_SIZE - 1) / BATCH_SIZE * NUM_EVENT_JOBS ))

# === CPU Optimization ===
AVAILABLE_CPUS=$(nproc)

if (( CPU > AVAILABLE_CPUS )); then
    echo "❌ ERROR: You requested $CPU CPUs, but only $AVAILABLE_CPUS are available."
    exit 1
fi

# Warn if using more than 75% of available CPUs
THREE_QUARTER_CPUS=$((AVAILABLE_CPUS * 3 / 4))
if (( CPU > THREE_QUARTER_CPUS )); then
    echo "⚠️ WARNING: You are using more than 75% of available CPUs ($CPU of $AVAILABLE_CPUS)."
    echo "Consider reducing CPU to avoid overloading your container."
fi

# === Adaptive Batch Size Calculation ===
TOTAL_WORK=$(( TOTAL_POINTS * TOTAL_EVENTS ))
ESTIMATED_TOTAL_JOBS=$(( (TOTAL_WORK + TARGET_EVENTS_PER_JOB - 1) / TARGET_EVENTS_PER_JOB ))
NUM_PARALLEL_JOBS=$(( ESTIMATED_TOTAL_JOBS > CPU ? ESTIMATED_TOTAL_JOBS : CPU ))
NUM_PARALLEL_JOBS=$(( NUM_PARALLEL_JOBS > 0 ? NUM_PARALLEL_JOBS : 1 ))
BATCH_SIZE=$(( (TOTAL_POINTS + NUM_PARALLEL_JOBS - 1) / NUM_PARALLEL_JOBS ))
NUM_EVENT_JOBS=$((TOTAL_EVENTS / NEVENTS))
NUM_EVENT_JOBS=$((NUM_EVENT_JOBS > 0 ? NUM_EVENT_JOBS : 1))
ACTUAL_JOBS=$(( (TOTAL_POINTS + BATCH_SIZE - 1) / BATCH_SIZE * NUM_EVENT_JOBS ))

echo "🧠 Adaptive batching:"
echo "  - Total work: $TOTAL_WORK events"
echo "  - Max CPUs available: $AVAILABLE_CPUS"
echo "  - CPUs requested: $CPU"
echo "  - Estimated batches based on event load: $ESTIMATED_TOTAL_JOBS"
echo "  - Parallel jobs scheduled: $NUM_PARALLEL_JOBS"
echo "  - Final batch size: $BATCH_SIZE"
echo "  - Actual jobs to be launched: $ACTUAL_JOBS"
echo ""
echo "🚦 Execution Plan:"
echo "  - Generate Design Points: $DO_GENERATE_DESIGN_POINTS"
echo "  - Run Model + Batch Jobs: $DO_BATCH_RUN"
echo "  - Rivet Merge & HTML:     $DO_RIVET_MERGE"
echo "  - Write Rivet Inputs:     $DO_WRITE_INPUTS"
echo ""

# === Generate Design Points ===
if [ "$DO_GENERATE_DESIGN_POINTS" = true ]; then
    echo "🔧 Generating design points..."
    python "$MAIN_SCRIPT" \
        --main_dir "$MAIN_DIR" \
        --clear_rivet_model True \
        --Get_Design_Points True \
        --Rivet_Setup True \
        --Run_Model False \
        --Run_Batch False \
        --Rivet_Merge False \
        --Write_input_Rivet False \
        --Coll_System ${COLLISIONS} \
        --nsamples "$TOTAL_POINTS"

    if [ $? -ne 0 ]; then
        echo "❌ Design point generation failed! NOT submitting jobs."
        exit 1
    fi
fi

# === Background job limiter ===
function wait_for_slot() {
    while [ "$(jobs -r | wc -l)" -ge "$CPU" ]; do
        sleep 0.5
    done
}

# === Batch Processing ===
if [ "$DO_BATCH_RUN" = true ]; then
    echo "📦 Starting batch processing..."
    
    # === Clean logs directory ===
    LOG_DIR="$MAIN_DIR/Batch_Rivet/logs"
    rm -rf "$LOG_DIR"
    mkdir -p "$LOG_DIR"

    m=0
    for ((j=0; j<TOTAL_EVENTS; j+=NEVENTS)); do
        ((m++))
        for ((i=0; i<TOTAL_POINTS; i+=BATCH_SIZE)); do
            start=$i
            end=$((i + BATCH_SIZE))
            [ $end -gt $TOTAL_POINTS ] && end=$TOTAL_POINTS
            l=$((i + m))
            SEED_DIFF=$(( (SEED + l - 1) % MAX_SEED + 1 ))

            wait_for_slot

            echo "🚀 Launching batch $start to $end (seed: $SEED_DIFF)"
            (
            python "$MAIN_SCRIPT" "$start" "$end" \
                --main_dir "$MAIN_DIR" \
                --clear_rivet_model False \
                --Get_Design_Points False \
                --Rivet_Setup False \
                --model_seed "$SEED_DIFF" \
                --nevents "$NEVENTS" \
                --Run_Batch True \
                --Run_Model True \
                --Rivet_Merge False \
                --Write_input_Rivet False \
                --Coll_System ${COLLISIONS} \
                > "$LOG_DIR/output_${start}_$l.log" \
                2> "$LOG_DIR/error_${start}_$l.log"

            echo "✅ Finished batch $start to $end (seed: $SEED_DIFF)"
            ) &
        done
    done
    wait

    echo "✅ All batches complete."
fi

# === Rivet Merge/HTML ===
if [ "$DO_RIVET_MERGE" = true ]; then
    echo "📝 Merging Rivet outputs and generating HTML..."
    for ((i=0; i<TOTAL_POINTS; i+=BATCH_SIZE)); do
        start=$i
        end=$((i + BATCH_SIZE))
        [ $end -gt $TOTAL_POINTS ] && end=$TOTAL_POINTS
        (
        python "$MAIN_SCRIPT" "$start" "$end" \
            --main_dir "$MAIN_DIR" \
            --clear_rivet_model False \
            --Get_Design_Points False \
            --Rivet_Setup False \
            --Run_Model False \
            --Run_Batch True \
            --Rivet_Merge True \
            --Write_input_Rivet False \
            --Coll_System ${COLLISIONS} \
            > "$LOG_DIR/output_html_${start}.log" \
            2> "$LOG_DIR/error_html_${start}.log"
        echo "✅ Finished batch $start to $end html reports"
        ) &
    done
    wait
fi

# === Write Rivet Inputs ===
if [ "$DO_WRITE_INPUTS" = true ]; then
    echo "Writing Data and Prediction inputs..."
    python "$MAIN_SCRIPT" \
        --main_dir "$MAIN_DIR" \
        --clear_rivet_model False \
        --Get_Design_Points False \
        --Run_Model False \
        --Run_Batch False \
        --Rivet_Merge False \
        --Write_input_Rivet True \
        --Coll_System ${COLLISIONS}
fi