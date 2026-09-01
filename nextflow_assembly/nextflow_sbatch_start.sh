#!/bin/bash
#SBATCH --job-name=nf            # Change CSC batch run name as needed
#SBATCH --time=60:00:00          # Change your runtime settings
#SBATCH --partition=small        # Change partition as needed
#SBATCH --account=${PROJECT}     # Add your project name here
#SBATCH --nodes=1                # Do not change
#SBATCH --cpus-per-task=40       # Change as needed
#SBATCH --mem-per-cpu=8G         # Increase as needed
#SBATCH --gres=nvme:600          # In GBs. Increase as needed

# Usage: 
# sbatch nextflow_sbatch2_start.sh \
# -i input_folder \
# -o output_folder \
# -w work_folder \
# -p profile_id \
# -a "other_arguments"

while getopts ":i:o:w:p:a:" opt; do
  case $opt in
    i)
      input_dir="$OPTARG"
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

# Prepend with argument
input_arg=""
if [[ -n "$input_dir" ]]; then
    input_arg="--input_dir $input_dir"
fi

# Write a copy of this file
cat ${0} > slurm-${SLURM_JOB_ID}.sh

# Write details of this job
cat > slurm-${SLURM_JOB_ID}.info <<EOT
Details for job slurm-${SLURM_JOB_ID}

Launch folder; includes logs, reports, and cache

$PWD


Command used to create the job  
NB: doesn't show quote marks, if any were present in the original command (e.g. in -a "<opts>")

sbatch <___start.sh> $*


Copy of .sh file from above; includes requested resources and path to the main .nf file

$PWD/slurm-${SLURM_JOB_ID}.sh


Derived nextflow command

nextflow run <___.nf> -ansi-log false ${input_arg} ${output_arg} ${work_arg} ${profile_arg} ${other_args}

EOT

# Preprocessing: compress any uncompressed FASTQ files
echo "Preprocessing: Compressing uncompressed FASTQ files in ${input_dir}..."
cd "${input_dir}"

# Check and compress uncompressed files
UNCOMPRESSED=$(find . -maxdepth 1 -name "*.fastq" -o -name "*.fq" | wc -l)
if [ $UNCOMPRESSED -gt 0 ]; then
    echo "Found $UNCOMPRESSED uncompressed files. Compressing..."
    find . -maxdepth 1 -name "*.fastq" -exec gzip {} \;
    find . -maxdepth 1 -name "*.fq" -exec gzip {} \;
    echo "Compression complete!"
else
    echo "All files already compressed."
fi

# Go back to working directory
cd -

# Run the pipeline
echo "Starting Nextflow pipeline..."

# Load Nextflow module
module load nextflow

# Actual Nextflow command
nextflow run /projappl/${PROJECT}/nextflow_assembly/full_assembly.nf -ansi-log false ${input_arg} ${output_arg} ${work_arg} ${profile_arg} ${other_args}
