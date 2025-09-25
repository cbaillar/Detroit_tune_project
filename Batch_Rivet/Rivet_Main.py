from Bayes_HEP.Design_Points import reader as Reader
from Bayes_HEP.Design_Points import design_points as DesignPoints
from Bayes_HEP.Design_Points import plots as Plots
from Bayes_HEP.Design_Points import rivet_html_parser as RivetParser

import argparse
import os
import shutil
import subprocess
import sys

###########################################################
################### SCRIPT PARAMETERS #####################
parser = argparse.ArgumentParser(description="Run Rivet/Model analysis pipeline.")

parser.add_argument("--main_dir", type=str, default="New_Project")
parser.add_argument("--seed", type=int, default=43)
parser.add_argument("--model_seed", type=int, default=283)
parser.add_argument("--clear_rivet_models", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--Get_Design_Points", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--nsamples", type=int, default=10)
parser.add_argument("--Rivet_Setup", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--model", type=str, default="pythia8")
parser.add_argument("--Run_Model", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--Run_Batch", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--PT_Min", type=int, default=-1)
parser.add_argument("--PT_Max", type=int, default=-1)
parser.add_argument("--nevents", type=int, default=1000)
parser.add_argument("--Rivet_Merge", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--Write_input_Rivet", type=lambda x: x.lower() == "true", default=True)
parser.add_argument("--Coll_System", nargs="+", default=["pp_7000"],
                    help="List of collision systems (e.g. pp_7000 pPb_5020)")

# Optional positional arguments for batching
parser.add_argument("batch_start", nargs="?", type=int, default=0)
parser.add_argument("batch_end", nargs="?", type=int, default=None) 

args = parser.parse_args()

# Override variables using args
main_dir = args.main_dir
seed = args.seed
model_seed = args.model_seed
clear_rivet_models = args.clear_rivet_models
Get_Design_Points = args.Get_Design_Points
nsamples = args.nsamples
Rivet_Setup = args.Rivet_Setup
model = args.model
Run_Model = args.Run_Model
Run_Batch = args.Run_Batch
PT_Min = args.PT_Min
PT_Max = args.PT_Max
nevents = args.nevents
Rivet_Merge = args.Rivet_Merge
Write_input_Rivet = args.Write_input_Rivet
batch_start = args.batch_start
batch_end = args.batch_end if args.batch_end is not None else nsamples
Coll_System = args.Coll_System

###########################################################
###########################################################

models_dir = f"{main_dir}/rivet/Models"
if clear_rivet_models and os.path.exists(models_dir):
    print(f"Clearing output directory: {models_dir}")
    shutil.rmtree(models_dir)


############## Design Points ####################

if Get_Design_Points: 
    print("Generating design points.")
    os.makedirs(f"{main_dir}/input/Design", exist_ok=True)
    Design_file = 'Design__Rivet.dat'
    output_file = f'{main_dir}/input/Design/{Design_file}'
    shutil.copy(f"{main_dir}/input/Rivet/parameter_prior_list.dat", output_file)

    RawDesign = Reader.ReadDesign(f'{main_dir}/input/Rivet/parameter_prior_list.dat')
    priors, parameter_names, dim= DesignPoints.get_prior(RawDesign)
    design_points = DesignPoints.get_design(nsamples, priors, seed)

    with open(output_file, 'a') as f:
    # Write index line based on row positions
        index_line = '\n' + "# Design point indices (row index): " + ' '.join(str(i) for i in range(len(design_points))) + '\n'
        f.write(index_line)

        # Write design points
        for row in design_points:
            f.write(' '.join(f"{val:.18e}" for val in row) + '\n')
    print(f"Appended {len(design_points)} design points to {output_file}")

else:
    print("Loading design points from input directory.")
    RawDesign = Reader.ReadDesign(f'{main_dir}/input/Design/Design__Rivet.dat')
    priors, parameter_names, dim= DesignPoints.get_prior(RawDesign)
    design_points = RawDesign['Design']

################# Rivet Analyses ####################
input_dir = f'{main_dir}/input/Rivet'
project_dir = f'{main_dir}/rivet'
analyses_file = 'analyses_list.txt'
tagged_analyses = {}
analyses_list = []
system_tag = None

print("Running Rivet.py with analyses_list.txt.")
os.makedirs(project_dir, exist_ok=True)

analyses_list = {}

with open(f"{input_dir}/{analyses_file}", 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        if line.endswith(':'):
            system_tag = line[:-1]
            tagged_analyses[system_tag] = {}
            if system_tag in Coll_System:
                analyses_list[system_tag] = []  # init list for this system
        elif system_tag is not None:
            parts = line.split()
            analysis = parts[0]
            histograms = parts[1:]
            tagged_analyses[system_tag][analysis] = histograms
            if system_tag in Coll_System:
                analyses_list[system_tag].append(analysis)
        else:
            raise ValueError(f"Found analysis line before tag: {line}")
    
missing_systems = [sys for sys in Coll_System if sys not in analyses_list]
if missing_systems:
    raise ValueError(f"❌ Missing analyses for the following system(s): {missing_systems}")

   
if Rivet_Setup:
    all_analyses = []
    for system in analyses_list:
        all_analyses.extend(analyses_list[system])

    print(f"📦 Building analyses: {all_analyses}")

    # Run the analysis build script
    subprocess.run([
        'bash',
        '/usr/local/share/Bayes_HEP/Design_Points/Rivet_Analyses/run_analysis.sh',
        ','.join(all_analyses),
        project_dir
    ], check=True)

with open(f"{project_dir}/analyses.log", 'r') as f:
    analyses_results = f.read().splitlines()

successful_builds = [line.split()[0] for line in analyses_results if line.strip().endswith('build_success')]
failed_builds = [line.split()[0] for line in analyses_results if line.strip().endswith('build_failed')]

print(f"✅ Analyses completed successfully: {successful_builds}")

if failed_builds:
    print(f"❌ Analyses with failed builds: {failed_builds}")
    sys.exit(1)
else:
    print("🎉 No failed builds!")

############# Run Model ###############
if Run_Model:
    if design_points is None:
        print("Design points not found. Need to generate design points first.")
        exit(1)

    if args.Run_Batch:
        batch_start = args.batch_start
        batch_end = args.batch_end if args.batch_end is not None else len(design_points)
    else:
        batch_start = 0
        batch_end = len(design_points)

    for system in Coll_System:
        if system not in analyses_list:
            print(f"⚠️ No analyses defined for system: {system}")
            continue

        System, Energy = system.split('_')
        print("🧪 Running model for system:", system)

        system_analyses = analyses_list[system]
        if not system_analyses:
            print(f"⚠️ No analyses listed for {system}")
            continue

        for i in range(batch_start, min(batch_end, len(design_points))):
            point = design_points[i]

            print(f"Running {model} for Design Point {i+1}: {point}")
            param_tag = DesignPoints.generate_param_tag(parameter_names, design_points[i])
            merge_tag = f"DP_{i+1}"
            model_seed_DP = model_seed * 10 + i 

            subprocess.run([
                'bash',
                f'/usr/local/share/Bayes_HEP/Design_Points/Models/{model}/scripts/run_{model}.sh',
                ','.join(system_analyses), input_dir, project_dir, System, Energy, str(nevents), str(model_seed), param_tag, merge_tag, str(PT_Min), str(PT_Max)], check=True)


############# Rivet Merge/HTML #################
if Rivet_Merge:
    if args.Run_Batch:
        batch_start = args.batch_start
        batch_end = args.batch_end if args.batch_end is not None else len(design_points)
    else:
        batch_start = 0
        batch_end = len(design_points)

    for system in Coll_System:
        System, Energy = system.split('_')

        system_analyses = analyses_list[system]
        print(system_analyses)
        if not system_analyses:
            print(f"⚠️ No analyses listed for {system}")
            continue

        for i, point in enumerate(design_points):
            
            merge_tag = f"DP_{i+1}"

            # Merge results
            subprocess.run(['bash', '/usr/local/share/Bayes_HEP/Design_Points/Rivet_Analyses/merge.sh', project_dir, model, System, Energy, merge_tag], check=True)
            
            # Generate HTML report
            subprocess.run(['bash', '/usr/local/share/Bayes_HEP/Design_Points/Rivet_Analyses/mkhtml.sh', project_dir, model, System, Energy, merge_tag], check=True)
            
############# Write out Data/Prediction Files #################
if Write_input_Rivet:
    os.makedirs(f"{main_dir}/input/Data", exist_ok=True)
    os.makedirs(f"{main_dir}/input/Prediction", exist_ok=True)
    
    for system in Coll_System:
        System, Energy = system.split('_')

        system_analyses = analyses_list[system]

        for i, point in enumerate(design_points):
            DP = i + 1
            for analysis in system_analyses:
                for hist in tagged_analyses[system][analysis]:
                    Experiment = analysis.split('_')[0]
                    base = f"{project_dir}/Models/{model}/html_reports/{model}_{System}_{Energy}_DP_{DP}_report.html/{analysis}/{hist}"
                    datafile = base + "__data.py"
                    labelfile = base + ".py"
                    obs, subobs = RivetParser.extract_labels(labelfile)

                    input_data_name = f"{main_dir}/input/Data/Data__{Energy}__{System}__{analysis}__{hist}"
                    input_pred_name = f"{main_dir}/input/Prediction/Prediction__{model}__{Energy}__{System}__{analysis}__{hist}"

                    RivetParser.extract_data(datafile, model, input_data_name, input_pred_name, obs, subobs, DP)

print("done")