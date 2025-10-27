#!/bin/bash
###### THIS IS FOR BATCHING JOBS WITH SLURM ON HPC

DO_GENERATE_DESIGN_POINTS=false
DO_PT_HAT_BINS=false
PT_EDGES=(15 20 25 30 40 60) 
DO_BATCH_RUN=false
DO_RIVET_MERGE=false
DO_WRITE_INPUTS=true

DO_DP_RERUN=false
DP_LIST=(2 4 6 8 14 18)
DP_SEED=(449862913 449863460 449862913 449863460 449862913 449863460)

# === Config ===
USER_DIR="/lustre/isaac24/proj/UTK0244/cbaillar"
COLLISIONS="pp_200" #"pp_7000 pp_13000"
TOTAL_POINTS=5        # Total number of design points
TOTAL_EVENTS=100000    # Total number of events
NEVENTS=1000000    # Events per job NOT USED ANYMORE

# === PATHS ===
MAIN_DIR="${WORKDIR:-/workdir}/Detroit_tune_Project"
MAIN_SCRIPT="$MAIN_DIR/Batch_Rivet/Rivet_Main.py"
PROJ_DIR="$USER_DIR/Bayes_HEP/Detroit_tune_Project"
HPC_DIR="$PROJ_DIR/Batch_Rivet/HPC"

CONTAINER="$USER_DIR/Bayes_HEP/bayes_hep.sif"
BIND_PATH="$USER_DIR/Bayes_HEP:/workdir"


echo "🧠 HPC Job Submission:"
echo "  - Total points: $TOTAL_POINTS"
echo "  - Events per job: $NEVENTS"
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

if [ "$DO_BATCH_RUN" = true ]; then
  if [ "$DO_PT_HAT_BINS" = false ]; then
    PT_EDGES=(-1 -1)
  fi

  if (( TOTAL_POINTS > 10 )); then
    max_idx=9
  else
    max_idx=$(( TOTAL_POINTS - 1 ))
  fi

  num_tasks=${#PT_EDGES[@]}

  echo "🔹 Submitting RUN Bins = $DO_PT_HAT_BINS"
  jid=$(sbatch --parsable --array=0-"$max_idx" --ntasks="$num_tasks" "$HPC_DIR/run_batch_array.slurm" \
       "$DO_PT_HAT_BINS" "${PT_EDGES[*]}" "$MAIN_DIR" "$MAIN_SCRIPT" \
       "$COLLISIONS" "$TOTAL_POINTS" "$TOTAL_EVENTS" "$CONTAINER" "$BIND_PATH")
  if [[ "$jid" =~ ^[0-9]+$ ]]; then
    run_jobids_all+=("$jid")
    # One key and one dependency: everything depends on this single job
    batch_key="batch_model"
    deps_by_batch[$batch_key]="$jid"
    echo "✅ Submitted: jobid=${jid}"
  else
    echo "❌ sbatch failed: $jid"
  fi
fi

# === Submit Design Point rerun jobs ===
if [ "$DO_DP_RERUN" = true ]; then
  if [ "$DO_PT_HAT_BINS" = false ]; then
    PT_EDGES=(-1 -1)
  fi
  echo "🔹 Submitting RUN Bins = $DO_PT_HAT_BINS (DP_LIST = ${DP_LIST[*]})"
  array_spec="0-$(( ${#DP_LIST[@]} - 1 ))"

  jid=$(sbatch --parsable --array="$array_spec" "$HPC_DIR/run_batch_array_rerunDP.slurm" \
       "$DO_PT_HAT_BINS" "${PT_EDGES[*]}" "${DP_LIST[*]}" "${DP_SEED[*]}" "$MAIN_DIR" "$MAIN_SCRIPT" \
       "$COLLISIONS" "$TOTAL_POINTS" "$TOTAL_EVENTS" "$CONTAINER" "$BIND_PATH")
  if [[ "$jid" =~ ^[0-9]+$ ]]; then
    run_jobids_all+=("$jid")
    # One key and one dependency: everything depends on this single job
    batch_key="batch_model"
    deps_by_batch[$batch_key]="$jid"
    echo "✅ Submitted: jobid=${jid}"
  else
    echo "❌ sbatch failed: $jid"
  fi
fi

# === Submit Rivet_Merge ===
merge_jobids_all=()

if [ "$DO_RIVET_MERGE" = true ]; then

    dep_str="${deps_by_batch[batch_model]:-}"  
    dep_flag=()
    if [[ -n "${dep_str}" ]]; then
        dep_flag=(--dependency="afterok:${dep_str}")
        echo "📦 Submitting MERGE after: ${dep_str}"
    else
        echo "📦 Submitting MERGE with NO dependency (no RUN jobs tracked)"
    fi

    jid=$(sbatch --parsable "${dep_flag[@]}" "$HPC_DIR/merge_batch_array.slurm" "$MAIN_DIR" "$MAIN_SCRIPT" "$COLLISIONS" "$TOTAL_POINTS" "$CONTAINER" "$BIND_PATH")
    if [[ "$jid" =~ ^[0-9]+$ ]]; then
        merge_jobids_all+=("$jid")
    else
        echo "❌ sbatch failed for MERGE [$start,$end): $jid"
    fi

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