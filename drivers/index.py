import os
import glob
import numpy as np

def get_design_index(main_dir):
    index_files = glob.glob(f"{main_dir}/input/Design/Design__Rivet__*.dat")
    index_files = [file for file in index_files if "Merged" not in file]
    index_numbers = [int(file.split("__")[-1].split(".")[0]) for file in index_files]
    return index_files

def get_max_design_index(main_dir):
    index_files = glob.glob(f"{main_dir}/input/Design/Design__Rivet__*.dat")
    index_files = [file for file in index_files if "Merged" not in file]
    index_numbers = [int(file.split("__")[-1].split(".")[0]) for file in index_files]
    max_index = max(index_numbers) if index_numbers else 0
    return index_files, max_index

def get_existing_design_points(index_files):
    existing_rows = []
    for oldfile in index_files:
        with open(oldfile) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                existing_rows.append(line)
    return existing_rows

def group_histograms_by_design(DG_predictions_files):
    hist_groups = {}
    for f in DG_predictions_files:
        parts = os.path.basename(f).split("__")
        parts = [p for p in parts if not p.startswith("DG")]
        key = "__".join(parts)
        hist_groups.setdefault(key, []).append(f)
    return hist_groups


def merge_histogram_groups(hist_groups, merged_dir):
    for key, DG_list in hist_groups.items():
        DG_list.sort(key=lambda index: int(index.split("__")[-2].split("G")[-1]))
        headers = [line for line in open(DG_list[0]) if line.startswith("#")][:-1]
        data = [np.loadtxt(f) for f in DG_list]
        merged = np.column_stack(data)
        with open(f"{merged_dir}/{key}", "w") as f:
            f.writelines(headers)
            f.write("# " + " ".join(f"design_point{i+1}" for i in range(merged.shape[1])) + "\n")
            np.savetxt(f, merged, fmt="%.6e")
