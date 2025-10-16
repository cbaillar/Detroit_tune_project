from Bayes_HEP.Design_Points import reader as Reader
from Bayes_HEP.Design_Points import design_points as DesignPoints
from Bayes_HEP.Design_Points import plots as Plots
from Bayes_HEP.Design_Points import data_pred as DataPred
from Bayes_HEP.Emulation import emulation as Emulation
from Bayes_HEP.Calibration import calibration as Calibration
from Bayes_HEP.Design_Points import rivet_html_parser as RivetParser
from Bayes_HEP.Design_Points import index as Index


import os
import shutil
import matplotlib.pyplot as plt
import glob
import dill
    
###########################################################
################### SCRIPT PARAMETERS #####################

work_dir= os.environ.get('WORKDIR', '/workdir')  # Default to /workdir
main_dir = f"{work_dir}/Detroit_tune_project"

seed = 43 

clear_output = True         #clear output directory
Coll_System = ['pp_200']   #['AuAu_200', 'PbPb_2760', 'PbPb_5020']

model = 'pythia8'
train_size = 90             #percentage of design points used for training
validation_size = 10        #percentage of design points used for validation

######## Emulators       
Train_Surmise = False
Load_Surmise = False

Train_Scikit = False
Load_Scikit = False

PCA = False 

######## Calibration
Run_Caibration = False 
nwalkers = 50
npool = 5               #Number of CPU to use for sampler
Samples = 100           #Number of MCMC samples  
nburn = 0.25 * Samples  #burn in samples
percent = 0.15          # Get traces for the last percentage of samples
Load_Calibration = False

####### Results 
size = 1000  # Number of samples for Results
Result_plots = False

###########################################################
###########################################################
output_dir = f"{main_dir}/output"
if clear_output and os.path.exists(output_dir):
    print(f"Clearing output directory: {output_dir}")
    shutil.rmtree(output_dir)
os.makedirs(output_dir, exist_ok=True)
os.makedirs(output_dir + "/plots", exist_ok=True)

############## Design Points ####################
index_files = Index.get_design_index(main_dir)
merged_Design_file = f"Design__Rivet__Merged.dat"
merged_output_file = f'{main_dir}/input/Design/{merged_Design_file}'
shutil.copy(f"{main_dir}/input/Rivet/parameter_prior_list.dat", merged_output_file)
existing_rows = Index.get_existing_design_points(index_files)

with open(merged_output_file, 'a') as f:
    f.write(f"\n\n# Total Design Points Merged = {len(existing_rows)}")
    f.write('\n' + "# Design point indices (row index): " + ' '.join(str(i) for i in range(len(existing_rows))) + '\n')   
    f.write("\n".join(existing_rows) + "\n")
print(f"➕ Appended {len(existing_rows)} design points to {merged_output_file}")
print(f"Loading {merged_Design_file} from input directory.") #(Leo: loading design points -> merged design points)

RawDesign = Reader.ReadDesign(f'{main_dir}/input/Design/{merged_Design_file}') #(Leo: changed the .dat file into the merged one)
priors, parameter_names, dim= DesignPoints.get_prior(RawDesign)
train_points, validation_points, train_indices, validation_indices = DesignPoints.load_data(train_size, validation_size, RawDesign['Design'], priors, seed)

Plots.plot_design_points(train_points, validation_points, priors)
plt.suptitle(f"Design Point Parameter Space", fontsize=18)
plt.savefig(f"{output_dir}/plots/Design_Points.png")
plt.show()

print("Loading input directory.")
prediction_dir = f"{main_dir}/input/Prediction"
data_dir = f"{main_dir}/input/Data"

DG_predictions_files = glob.glob(f"{prediction_dir}/*.dat")
merged_dir = f"{main_dir}/input/Prediction_Merged"
os.makedirs(merged_dir, exist_ok=True)

hist_groups = Index.group_histograms_by_design(DG_predictions_files)
Index.merge_histogram_groups(hist_groups, merged_dir)

Data = {}
Predictions = {}
all_data = {}
n_hist = {}

for system in Coll_System:
    System, Energy = system.split('_')[0], system.split('_')[1]  
    sys = System + Energy   

    prediction_files = glob.glob(os.path.join(merged_dir, f"Prediction__{model}__{Energy}__{System}__*__values.dat")) #(Leo: re-path to merged_dir)
    data_files = glob.glob(os.path.join(data_dir, f"Data__{Energy}__{System}__*.dat"))

    all_predictions = [Reader.ReadPrediction(f) for f in prediction_files]
    all_data[sys] = [Reader.ReadData(f) for f in data_files]

    n_hist[sys] = len(prediction_files)

    x, x_errors, y_data_results, y_data_errors = DataPred.get_data(all_data[sys], sys)
    y_train_results, y_train_errors, y_val_results, y_val_errors = DataPred.get_predictions(all_predictions, train_indices, validation_indices, sys)

print("Data and predictions loaded successfully.")
raise SystemExit("Stopping script here")

######### Emulators ########
Emulators = {}
PredictionVal = {}
PredictionTrain = {}
os.makedirs(output_dir + "/emulator", exist_ok=True)

######### Surmise Emulator ########
if Train_Surmise:
    print("Training Surmise emulators.")
    method_type = 'indGP'
    if PCA:
        method_type = 'PCGP'

    Emulators['surmise'], PredictionVal['surmise_val'], PredictionTrain['surmise_train'] = Emulation.train_surmise(Emulators, x, y_train_results, train_points, validation_points, output_dir, method_type)
elif Load_Surmise:
    print("Loading Surmise emulator.")
    Emulators['surmise'] = {}
    Emulators['surmise'], PredictionVal['surmise_val'], PredictionTrain['surmise_train'] = Emulation.load_surmise(Emulators['surmise'], x, train_points, validation_points, output_dir)

######## Scikit-learn Emulator ########
if Train_Scikit:
    print("Training Scikit-learn emulator.")
    method_type = 'GP'
    if PCA:
        print("PCA is not supported for Scikit-learn emulator. Using standard Gaussian Process.") 
        
    Emulators['scikit'], PredictionVal['scikit_val'], PredictionTrain['scikit_train'] = Emulation.train_scikit(Emulators, x, y_train_results, train_points, validation_points, output_dir, method_type)
elif Load_Scikit:
    print("Loading Scikit-learn emulator.")

    Emulators['scikit'] = {}
    Emulators['scikit'], PredictionVal['scikit_val'], PredictionTrain['scikit_train'] = Emulation.load_scikit(Emulators['scikit'], x, train_points, validation_points, output_dir)
 
os.makedirs(f"{output_dir}/plots/emulators/", exist_ok=True)

Plots.plot_rmse_comparison(y_train_results, y_val_results, PredictionTrain, PredictionVal, output_dir)

########### Calibration ###########
if Run_Caibration:
    print("Running calibration.")
    os.makedirs(f"{output_dir}/calibration/samples/", exist_ok=True)
    os.makedirs(f"{output_dir}/calibration/pos0/", exist_ok=True)
    os.makedirs(f"{output_dir}/plots/calibration/", exist_ok=True)  
    os.makedirs(f"{output_dir}/plots/trace/", exist_ok=True)

    results, samples_results, min_samples, map_params = Calibration.run_calibration(x, y_data_results, y_data_errors, priors, Emulators, output_dir, nburn, nwalkers, npool, Samples)
    
    Calibration.get_traces(output_dir, x, samples_results, Emulators, parameter_names, percent) 

if Load_Calibration:
    print("Calibration not performed. Loading Samples.")
    samples_results, min_samples, map_params= Calibration.load_samples(output_dir, x, Emulators)

########### Results ###########

if Result_plots:
    print("Generating results plots.")
    
    if min_samples < size:
        print(f"Warning: Minimum samples ({min_samples}) is less than requested size ({size}). Adjusting size to {min_samples}.")
        size = min_samples

    Plots.results(size, x, all_data, samples_results, y_data_results, y_data_errors, Emulators, n_hist, output_dir)
    
print("done")
