#!/bin/bash
#SBATCH -J write_inputs
#SBATCH -A ISAAC-UTK0244
#SBATCH --qos=campus
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=10
#SBATCH --partition=campus
#SBATCH --time=0-01:00:00
#SBATCH --error=/lustre/isaac24/scratch/cbaillar/jobs/error/job.e%J
#SBATCH --output=/lustre/isaac24/scratch/cbaillar/jobs/output/job.o%J

########### USER-CUSTOMIZABLE VARIABLES #################

USER_DIR="/lustre/isaac24/proj/UTK0244/cbaillar"
COLLISIONS="pp_200"
MODEL="pythia8"
N_WALKERS=50        # Number of Random walkers for emcee sampler
NPOOL=10
SAMPLES=10000         # Number of samples for MCMC
RESULT_SIZE=100


WORKDIR="${WORKDIR:-/workdir}"
MAIN_DIR="$WORKDIR/Detroit_tune_Project"
MAIN_SCRIPT="$MAIN_DIR/Batch_Rivet/Bayes_Main.py"

CONTAINER="$USER_DIR/Bayes_HEP/bayes_hep.sif"
BIND_PATH="$USER_DIR/Bayes_HEP:/workdir"

#########################################################

apptainer exec --bind "$BIND_PATH" "$CONTAINER" \
    python "$MAIN_SCRIPT" \
        --main_dir "$MAIN_DIR" \
        --clear_output False \
        --Coll_System ${COLLISIONS} \
        --model "$MODEL" \
        --train_size 80 --validation_size 20 \
        --Train_Surmise True --Train_Scikit True --PCA True \
        --Run_Calibration True --Load_Calibration True --nwalkers "$N_WALKERS" --npool "$NPOOL" --Samples "$SAMPLES" \
        --size "$RESULT_SIZE" 