#!/bin/bash
#SBATCH -J merge_batch
#SBATCH -A ISAAC-UTK0244
#SBATCH --qos=campus
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --partition=campus
#SBATCH --time=0-01:00:00
#SBATCH --error=/lustre/isaac24/scratch/cbaillar/jobs/error/job.e%J
#SBATCH --output=/lustre/isaac24/scratch/cbaillar/jobs/output/job.o%J

DP_START=$1
DP_END=$2
MAIN_DIR=$3
MAIN_SCRIPT=$4
COLLISIONS=$5
CONTAINER=$6
BIND_PATH=$7

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