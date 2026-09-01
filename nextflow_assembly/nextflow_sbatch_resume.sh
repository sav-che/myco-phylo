#!/bin/bash
#SBATCH --job-name=nfr           # Change CSC batch run name as needed
#SBATCH --time=30:00:00          # Change your runtime settings
#SBATCH --partition=small        # Change partition as needed
#SBATCH --account=${PROJECT}     # Add your project name here
#SBATCH --nodes=1                # Do not change
#SBATCH --cpus-per-task=40       # Change as needed
#SBATCH --mem-per-cpu=8G         # Increase as needed
#SBATCH --gres=nvme:600          # In GBs. Increase as needed

# Usage:
# sbatch nextflow_sbatch2_resume.sh \
# -i input_folder \
# -o output_folder \
# -w work_folder \
# -p profile_id \
# -a "other_arguments" \
# -r run_id

while getopts ":i:o:w:p:a:r:" opt; do
  case $opt in
    i)
      input_arg="--input_dir $OPTARG"
      ;;
    o)
      output_arg="-output-dir $OPTARG"
      ;;
    w)
      work_arg="-work-dir $OPTARG"
      ;;
    p)
      profile_arg="-profile $OPTARG"
      ;;
    a)
      other_args="$OPTARG"
      ;;
    r)
      resume_id="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument"
      exit 1
      ;;
  esac 
done

# Write a copy of this file
cat ${0} > slurm-${SLURM_JOB_ID}.sh

# Write details of this job
cat > slurm-${SLURM_JOB_ID}.info <<EOT
Details for job slurm-${SLURM_JOB_ID}

Launch folder; includes logs, reports, and cache

$PWD


Command used to create the job  
NB: doesn't show quote marks, if any were present in the original command (e.g. in -a "<opts>")

sbatch <___resume.sh> $*


Copy of .sh file from above; includes requested resources and path to the main .nf file

$PWD/slurm-${SLURM_JOB_ID}.sh


Derived nextflow command

nextflow run <___.nf> -ansi-log false ${input_arg} ${output_arg} ${work_arg} ${profile_arg} ${other_args} -resume ${resume_id}

EOT

# Load Nextflow module
module load nextflow

# Actual Nextflow command
nextflow run /projappl/${PROJECT}/nextflow_assembly/full_assembly.nf -ansi-log false ${input_arg} ${output_arg} ${work_arg} ${profile_arg} ${other_args} -resume ${resume_id} 