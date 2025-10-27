#!/bin/bash
#SBATCH -J batch_model
#SBATCH -A ISAAC-UTK0244
#SBATCH --qos=campus
#SBATCH --partition=campus
#SBATCH --time=023:55:00
#SBATCH --array=0-9           # mod 10 design points
#SBATCH --ntasks=4             # 4 chunks per DP, run in parallel
#SBATCH --cpus-per-task=1
#SBATCH --error=/lustre/isaac24/scratch/cbaillar/jobs/error/job.e%A_%a
#SBATCH --output=/lustre/isaac24/scratch/cbaillar/jobs/output/job.o%A_%a

DO_PT_HAT_BINS=$1
PT_EDGES_STR=$2
MAIN_DIR=$3
MAIN_SCRIPT=$4
COLLISIONS=$5
NUM_DP=$6
NEVENTS=$7
CONTAINER=$8
BIND_PATH=$9


if (( NUM_DP > 10 )); then
    DP_PER=$(( NUM_DP / 10 ))
else
    DP_PER=1
fi


DP_START=$((SLURM_ARRAY_TASK_ID * DP_PER ))
DP_END=$((DP_START + DP_PER ))

start_time=$(date +%s)

read -r -a PT_EDGES <<< "$PT_EDGES_STR"

echo "DP ${SLURM_ARRAY_TASK_ID} → range [$((DP_START+1)),${DP_END}]"
echo "$PT_EDGES"


RUN_BATCH_FUNC() {
    local PT_MIN=$1
    local PT_MAX=$2
    local SEED=$3
        
    srun --exclusive -n1 -N1 bash -c "
	    unset PYTHIA8DATA

        apptainer exec --bind "$BIND_PATH" "$CONTAINER" \
            python "$MAIN_SCRIPT" "$DP_START" "$DP_END" \
            --main_dir "$MAIN_DIR" \
            --clear_rivet_model False \
            --Get_Design_Points False \
            --Rivet_Setup False \
            --model_seed "$SEED" \
            --nevents "$NEVENTS" \
            --Run_Model True \
            --Run_Batch True \
            --PT_Min "$PT_MIN"\
            --PT_Max "$PT_MAX"\
            --Rivet_Merge False \
            --Write_input_Rivet False \
            --Coll_System ${COLLISIONS}
    "
}

if [ "$DO_PT_HAT_BINS" = true ]; then
    for ((k=0; k<${#PT_EDGES[@]}-1; k++)); do
        SEED=$(( SLURM_JOB_ID*100 + SLURM_ARRAY_TASK_ID*10 + k))
        MIN=${PT_EDGES[k]}
        MAX=${PT_EDGES[k+1]}
        echo "🧱 Bin ${MIN}-${MAX}"
        RUN_BATCH_FUNC "$MIN" "$MAX" "$SEED" &
    done
    k=${#PT_EDGES[@]}-1
    SEED=$(( SLURM_JOB_ID*100 + SLURM_ARRAY_TASK_ID*10 + k))
    LAST_MIN=${PT_EDGES[-1]}
    echo "🧱 Bin > ${LAST_MIN}"
    RUN_BATCH_FUNC "$LAST_MIN" -1 "$SEED" &
    wait
else
    #SEED=$(( SLURM_JOB_ID*100 + SLURM_ARRAY_TASK_ID*10 ))
    #RUN_BATCH_FUNC -1 -1 "$SEED"
    for j in {0..5}; do
        SEED=$(( SLURM_JOB_ID*100 + SLURM_ARRAY_TASK_ID*10 + j ))
        RUN_BATCH_FUNC -1 -1 "$SEED" &
    done
    wait
fi

end_time=$(date +%s)
runtime=$((end_time - start_time))
echo "⏱️ Total runtime: ${runtime} seconds ($(printf '%02d:%02d:%02d\n' $((runtime/3600)) $((runtime%3600/60)) $((runtime%60))))"