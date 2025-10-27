#!/bin/bash
#SBATCH -J merge_batch
#SBATCH -A ISAAC-UTK0244
#SBATCH --qos=short
#SBATCH --partition=short
#SBATCH --time=02:55:00
#SBATCH --array=0-4           # mod 5 design points
#SBATCH --ntasks=4             # 4 chunks per DP, run in parallel
#SBATCH --cpus-per-task=1
#SBATCH --error=/lustre/isaac24/scratch/cbaillar/jobs/error/job.e%A_%a
#SBATCH --output=/lustre/isaac24/scratch/cbaillar/jobs/output/job.o%A_%a

MAIN_DIR=$1
MAIN_SCRIPT=$2
COLLISIONS=$3
NUM_DP=$4
CONTAINER=$5
BIND_PATH=$6

DP_PER=$((NUM_DP / 5))


DP_START=$((SLURM_ARRAY_TASK_ID * DP_PER ))
DP_END=$((DP_START + DP_PER ))

echo "🧪 Merging batch $DP_START to $DP_END"

apptainer exec --bind "$BIND_PATH" "$CONTAINER" \
    python "$MAIN_SCRIPT" "$DP_START" "$DP_END" \
    --main_dir "$MAIN_DIR" \
    --clear_rivet_model False \
    --Get_Design_Points False \
    --Rivet_Setup False \
    --Run_Model False \
    --Run_Batch True \
    --Rivet_Merge True \
    --Write_input_Rivet False \
    --Coll_System ${COLLISIONS}