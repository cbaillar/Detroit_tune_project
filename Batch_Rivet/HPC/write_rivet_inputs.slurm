#!/bin/bash
#SBATCH -J write_inputs
#SBATCH -A ISAAC-UTK0244
#SBATCH --qos=campus
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --partition=campus
#SBATCH --time=0-01:00:00
#SBATCH --error=/lustre/isaac24/scratch/cbaillar/jobs/error/job.e%J
#SBATCH --output=/lustre/isaac24/scratch/cbaillar/jobs/output/job.o%J

# === Get arguments ===
MAIN_DIR="$1"
MAIN_SCRIPT="$2"
COLLISIONS="$3"
CONTAINER="$4"
BIND_PATH="$5"

apptainer exec --bind "$BIND_PATH" "$CONTAINER" \
    python "$MAIN_SCRIPT" \
        --main_dir "$MAIN_DIR" \
        --clear_rivet_model False --Get_Design_Points False \
        --Run_Model False --Run_Batch False --Rivet_Merge False --Write_input_Rivet True \
        --Coll_System ${COLLISIONS}