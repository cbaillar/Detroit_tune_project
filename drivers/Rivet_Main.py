from Bayes_HEP.Design_Points import reader as Reader
from Bayes_HEP.Design_Points import design_points as DesignPoints
from Bayes_HEP.Design_Points import plots as Plots
from Bayes_HEP.Design_Points import rivet_html_parser as RivetParser

import os
import shutil
import subprocess
import sys

###########################################################
################### SCRIPT PARAMETERS #####################
work_dir= os.environ.get('WORKDIR', '/workdir')  # Default to /workdir
main_dir = f"{work_dir}/Detroit_tune_Project"
seed = 43                   #seed for LHS
model_seed = 283            #seed for model

clear_rivet_models = True          #clear rivet directory
Coll_System = ['pp_200']   # ['pp_200', 'pp_7000'] 
Get_Design_Points = True   #True: uses LHS to get design points False: loads design points in input file
Rivet_Setup = True
nsamples = 5              #number of design points
model = 'pythia8'           #only pythia8 (atm)
Run_Model = True            #run design points through model and Rivet
PT_Min = -1 
PT_Max = -1
nevents = 100             # number of events for model in each run
Rivet_Merge =True
Write_input_Rivet = True   #gets Data/Pred info from html files 

###########################################################
###########################################################
os.makedirs(f"{main_dir}/rivet", exist_ok=True)

models_dir = f"{main_dir}/rivet/Models"
if clear_rivet_models and os.path.exists(models_dir):
    print(f"Clearing output directory: {models_dir}")
    shutil.rmtree(models_dir)

############## Design Points ####################

if Get_Design_Points: 
    print("Generating design points.")
    os.makedirs(f"{main_dir}/input/Design", exist_ok=True)

    ###
    if () :
        n =

    Design_file = 'Design__Rivet__' + n +  '.dat'
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

# Parse the build log
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

############ Run Model/Rivet ###############
if Run_Model:
    if design_points is None:
        print("Design points not found. Need to generate design points first.")
        exit(1)

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

        for i, point in enumerate(design_points):
            print(f"🚀 Running {model} for Design Point {i+1}: {point}")
            param_tag = DesignPoints.generate_param_tag(parameter_names, point)
            merge_tag = f"DP_{i+1}"

            subprocess.run([
                'bash', f'/usr/local/share/Bayes_HEP/Design_Points/Models/{model}/scripts/run_{model}.sh',
                ','.join(system_analyses), input_dir, project_dir, System, Energy, str(nevents), str(model_seed), param_tag, merge_tag, PT_Min, PT_Max], check=True)

############# Rivet Merge/HTML #################
if Rivet_Merge:
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
            print(system_analyses)

            for i, point in enumerate(design_points):
                DP = i + 1

                for analysis in system_analyses:
                    for hist in tagged_analyses[system][analysis]:
                        base = f"{project_dir}/Models/{model}/html_reports/{model}_{System}_{Energy}_DP_{DP}_report.html/{analysis}/{hist}"
                        datafile = base + "__data.py"
                        labelfile = base + ".py"
                        obs, subobs = RivetParser.extract_labels(labelfile)

                        input_data_name = f"{main_dir}/input/Data/Data__{Energy}__{System}__{analysis}__{hist}"
                        input_pred_name = f"{main_dir}/input/Prediction/Prediction__{model}__{Energy}__{System}__{analysis}__{hist}"

                        RivetParser.extract_data(datafile, model, input_data_name, input_pred_name, obs, subobs, DP)


print("done")