#!/bin/bash
#SBATCH -J batch_model
#SBATCH -A ISAAC-UTK0244
#SBATCH --qos=campus
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=10
#SBATCH --cpus-per-task=1  
#SBATCH --partition=campus
#SBATCH --time=0-01:00:00
#SBATCH --error=/lustre/isaac24/scratch/cbaillar/jobs/error/job.e%J
#SBATCH --output=/lustre/isaac24/scratch/cbaillar/jobs/output/job.o%J

DP_START=$1
DP_END=$2
MAIN_DIR=$3
MAIN_SCRIPT=$4
COLLISIONS=$5
NEVENTS=$6
CONTAINER=$7
BIND_PATH=$8
PT_MIN=$9
PT_MAX=${10}

SEED=$SLURM_JOB_ID

echo "🚀 SLURM Job ID: $SLURM_JOB_ID"
echo "📦 Running design points: $DP_START to $DP_END"
echo "🎲 Using seed: $SEED"

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

if [ $? -ne 0 ]; then
    echo "❌ Job failed: $DP_START to $DP_END"
    exit 1
fi