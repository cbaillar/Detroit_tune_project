#!/bin/bash
###### THIS IS FOR BATCHING JOBS WITH SLURM ON HPC

DO_GENERATE_DESIGN_POINTS=true
DO_PT_HARD_BINS=true
PT_EDGES=(5 10 20 30 40 50 60 70) 
DO_BATCH_RUN=true
DO_RIVET_MERGE=true
DO_WRITE_INPUTS=true

# === Config ===
USER_DIR="/lustre/isaac24/proj/UTK0244/cbaillar"
COLLISIONS="pp_200" #"pp_7000 pp_13000"
TOTAL_POINTS=10        # Total number of design points
TOTAL_EVENTS=100    # Total number of events
NEVENTS=100        # Events per job

# === PATHS ===
MAIN_DIR="${WORKDIR:-/workdir}/Detroit_tune_Project"
MAIN_SCRIPT="$MAIN_DIR/Batch_Rivet/Rivet_Main.py"
PROJ_DIR="$USER_DIR/Bayes_HEP/Detroit_tune_Project"
HPC_DIR="$PROJ_DIR/Batch_Rivet/HPC"

CONTAINER="$USER_DIR/Bayes_HEP/bayes_hep.sif"
BIND_PATH="$USER_DIR/Bayes_HEP:/workdir"

# === Derived Values ===
NUM_EVENT_JOBS=$((TOTAL_EVENTS / NEVENTS))
NUM_EVENT_JOBS=$((NUM_EVENT_JOBS > 0 ? NUM_EVENT_JOBS : 1))

BATCH_SIZE=10 #this needs to match #SBATCH --ntasks-per-node=10
NUM_BATCHES=$(( (TOTAL_POINTS + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "🧠 HPC Job Submission:"
echo "  - Total points: $TOTAL_POINTS"
echo "  - Events per job: $NEVENTS"
echo "  - Design points per batch: $BATCH_SIZE"
echo "  - Event batches: $NUM_EVENT_JOBS"
echo "  - Design batches: $NUM_BATCHES"
echo "  - Total jobs: $((NUM_BATCHES * NUM_EVENT_JOBS))"
echo ""

# === Generate Design Points (once) ===
if [ "$DO_GENERATE_DESIGN_POINTS" = true ]; then
    apptainer exec --bind "$BIND_PATH" "$CONTAINER" \
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

# === Submit SLURM jobs ===
run_jobids_all=()
declare -A deps_by_batch

RUN_BATCH_FUNC() {
  local PT_MIN="$1"
  local PT_MAX="$2"
  local round=0

  for ((j=0; j<TOTAL_EVENTS; j+=NEVENTS)); do
    ((round++))
    for ((i=0; i<TOTAL_POINTS; i+=BATCH_SIZE)); do
      start=$i
      end=$((i + BATCH_SIZE)); [ $end -gt $TOTAL_POINTS ] && end=$TOTAL_POINTS
      batch_key="${start}:${end}"

      echo "🔹 Submitting RUN [$start,$end) round=$round (events $NEVENTS) PT_MIN=$PT_MIN PT_MAX=$PT_MAX"
      jid=$(sbatch --parsable "$HPC_DIR/run_batch.slurm" \
           "$start" "$end" "$MAIN_DIR" "$MAIN_SCRIPT" \
           "$COLLISIONS" "$NEVENTS" "$CONTAINER" "$BIND_PATH" \
           "$PT_MIN" "$PT_MAX")
      if [[ "$jid" =~ ^[0-9]+$ ]]; then
        run_jobids_all+=("$jid")
        if [ -z "${deps_by_batch[$batch_key]+x}" ]; then
          deps_by_batch[$batch_key]="$jid"
        else
          deps_by_batch[$batch_key]="${deps_by_batch[$batch_key]}:$jid"
        fi
      else
        echo "❌ sbatch failed for RUN [$start,$end): $jid"
      fi
    done
  done
}

if [ "$DO_BATCH_RUN" = true ]; then
  if [ "$DO_PT_HARD_BINS" = true ]; then
    for ((k=0; k<${#PT_EDGES[@]}-1; k++)); do
      MIN=${PT_EDGES[k]}
      MAX=${PT_EDGES[k+1]}
      echo "🧱 Bin ${MIN}-${MAX}"
      RUN_BATCH_FUNC "$MIN" "$MAX"
    done
    LAST_MIN=${PT_EDGES[-1]}
    echo "🧱 Bin > ${LAST_MIN}"
    RUN_BATCH_FUNC "$LAST_MIN" -1
  else
    RUN_BATCH_FUNC -1 -1
  fi
fi

# === Submit Rivet_Merge stage (per batch) ===
merge_jobids_all=()

if [ "$DO_RIVET_MERGE" = true ]; then
    for ((i=0; i<TOTAL_POINTS; i+=BATCH_SIZE)); do
        start=$i
        end=$((i + BATCH_SIZE))
        [ $end -gt $TOTAL_POINTS ] && end=$TOTAL_POINTS
        batch_key="${start}:${end}"

        dep_str="${deps_by_batch[$batch_key]}"
        dep_flag=()
        if [ -n "$dep_str" ]; then
            dep_flag=(--dependency="afterok:$dep_str")
            echo "📦 Submitting MERGE for [$start,$end) after: $dep_str"
        else
            echo "📦 Submitting MERGE for [$start,$end) with NO dependency (no RUN jobs tracked)"
        fi

        jid=$(sbatch --parsable "${dep_flag[@]}" "$HPC_DIR/merge_batch.slurm" "$start" "$end" "$MAIN_DIR" "$MAIN_SCRIPT" "$COLLISIONS" "$CONTAINER" "$BIND_PATH")
        if [[ "$jid" =~ ^[0-9]+$ ]]; then
            merge_jobids_all+=("$jid")
        else
            echo "❌ sbatch failed for MERGE [$start,$end): $jid"
        fi
    done
fi

# === Submit Write Phase ===
if [ "$DO_WRITE_INPUTS" = true ]; then
    dep_flag=()
    if [ "$DO_RIVET_MERGE" = true ] && [ "${#merge_jobids_all[@]}" -gt 0 ]; then
        write_dep=$(IFS=:; echo "${merge_jobids_all[*]}")
        dep_flag=(--dependency="afterok:$write_dep")
        echo "📄 Submitting WRITE after MERGE jobs: $write_dep"
    elif [ "$DO_BATCH_RUN" = true ] && [ "${#run_jobids_all[@]}" -gt 0 ]; then
        write_dep=$(IFS=:; echo "${run_jobids_all[*]}")
        dep_flag=(--dependency="afterok:$write_dep")
        echo "📄 Submitting WRITE after RUN jobs: $write_dep"
    else
        echo "📄 Submitting WRITE with NO dependency (no prior jobs or phases disabled)"
    fi

    sbatch "${dep_flag[@]}" "$HPC_DIR/write_rivet_inputs.slurm" "$MAIN_DIR" "$MAIN_SCRIPT" "$COLLISIONS" "$CONTAINER" "$BIND_PATH"
fi