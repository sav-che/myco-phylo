# Assembly from raw reads to spades meta (with busco and quast reports)

### Location of the pipeline: projappl/${PROJECT}/nextflow_assembly/

It contains 
* `full_assembly.nf` file
* `params.config` file with parameters for programs and templates for genomic plates with custom parameters
* `nextflow.config` file for nextflow maintenance-side configuration
* sbatch `.sh` scripts to launch pipeline on HPC with SLURM
* modules - code for running individual programs, wrapped for nextflow; nf-core modules modified for our HPC and local ones
* subworkflows - sequences of programs separated for convenience of reuse
* databases - place for small databases
* supporting scripts - for post-pipeline result polish

### Sbatch configuration

`nexflow_sbatch_start.sh` and `nextflow_sbatch_resume.sh`. Everything from older files generally applies, except the way arguments provided is different - see [Usage section](#Usage).
Always check resource allocation before starting, may be edited by other people.

#### Puhti

<details>
<summary>Puhti is being decommissioned - to be updated for Roihu</summary>

When running genomes in batches of 20, small partition is sufficient. It is better to reserve a full node by stating the number of cores (40) and memory requirement (8GB), because not all nodes have 40*8GB of memory. Reserving only 7GB will often cause Kraken to terminate. NVME-memory is short in Puhti and highly competed. Set as low as possible; 600GB works with the pipeline and FCS-GX.

For a plate-wide runs, it makes sense to reserve resources of an entire node by setting `cpus-per-task=40` and `gres=nvme:3600`.
</details>

#### LUMI

On LUMI it's best to request an entire LUMI-C node and all memory on it. Relevant sbatch directives:
```sh
#SBATCH --time=48:00:00
#SBATCH --partition=standard
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --mem=0
```

* Start scripts run the pipeline from zero; it checks whether any fastq files are unzipped, and, if so, gzip them
* resume scripts continue it after something went wrong (usually, that's time and memory limits).

### Workflow description

* Takes fastq.gz reads;
*  applies fastp (currently with 15 bp head trimming and 2 bp tail trimming);
*  applies Kraken with standard database (typical lab and human contamination) and a confidence parameter of 0.5 (quite a strict value);
*  visualizes Kraken results with Krona;
* takes unclassified reads from Kraken and directs them to SPAdes meta assembler (aka "SPAdes all-reads");
* takes scaffolds, contigs, and 3 versions of assembly graph to the spades result directory;
* the assembly is evaluated in QC workflow (Busco (basidiomycota line), quast, MMseqs2 vs UNITE/EUKARYOME, MerquryFK);
* the reads (Kraken unclassified) are mapped to the scaffolds (bwa_mapping folder).
* the reads (Kraken unclassified) are used by GetOrganelle (SPAdes-based) to assemble nrDNA and mitochondria.
* nrDNA is searched with MMseqs2 vs UNITE/EUKARYOME. 
* the reads (Kraken unclassified) are mapped to nrDNA and mitochondria (if produced).
* the reads without nrDNA and mitochondria are assembled by SPAdes meta (aka "SPAdes no-NRMT")
* no-NRMT assembly is evaluated by QC workflow to compare with all-reads assembly and nrDNA.
* FCS-GX decontamination is run on a no-NRMT assembly, and (TBA) non-target contigs excluded.
* TBA: QC workflow on FCS-GX-decontaminated assembly and comparison with MultiQC with previous QCs.

### Usage

New `sbatch` scripts. These are made for named - not positional - arguments. 

#### Options

All are optional except `-i`. 
option|nextflow meaning|note
---|---|---|
`-i` | `--input_dir` | Folder with input `fastq(.gz)\|fq(.gz)` files. Obligatory.
`-o` | `-output-dir` | Folder for user-friendly output. If not specified, defaults to `results` in launch folder - problematic for projappl
`-w` | `-work-dir` | Folder for machine-friendly output. If not specified, defaults to `work` in launch folder - not suitable for projappl
`-p` | `-profile` | E.g., HPC- or plate-specific options; for valid values see names of top-level closures in `profile {}` block in `*.config` files.
`-a` | other params | To override defaults from `params{}` block of `params.config`. Must be **quoted** (if multiple, all arguments in the same quote): `-a "--arg1 value1 -arg2 value2"`
`-r` | `-resume` | Only for `_resume.sh`: if you need to continue from any other run but the latest, specify its ID, e.g., mnemonic name shown in `[]` after launch

Mind that most of program-specific options are not exposed in `params{}` - instead edit them in `process{}` block, if needed. 

Important inputs for `-a`:

`--spades_on_all_reads` - Can be `true|false`, default: `true`. run SPAdes on all post-Kraken reads, or wait for getOrganelle to finish, and then run only on reads without nrDNA/mitochondria? 

`--samplesheet` - Can be `null|path`, default: `null`. If path, should be 2-column TAB-separated headerless file that maps file basenames without `_R.*` to nicer labels. If `null`, and `-p` is specified, will truncate basename after N underscores based on value in `-p` profile. If `null`, and `-p` is not specified, will truncate everything after 1st underscore. 
Example samplesheet:
```
A001_Dacrymyces_sp1_S185_L001	A001_Dacrymyces_sp1
A002_Dacrymyces_sp2_S193_L001	A002_Dacrymyces_sp2
A003_Dacrymyces_sp3_S233_L001	A003_Dacrymyces_sp3
```

Otherwise, only the raw names' Nth part (delimiter with underscores), can be taken as a label:
```sh
-a "--sample_name_parts 1"
```

#### New run

> [!WARNING]
> It is not advised to launch from `/projappl/${PROJECT}/nextflow_assembly` because it is not possible to simultaneously launch multiple instances (= sbatch jobs) of the same pipeline from it. Instead, make separate launch folder for each instance.

1. Create a launch folder for your run in scratch, e.g., `/scratch/${PROJECT}/nextflow/launch_12345`
2. Copy the `_start.sh` and `_resume.sh` files into it.
3. **`cd` to this folder**
4. Edit resources in these files to your liking.
5. Launch pipeline as follows. Only input (`-i`) is obligatory. If not specified, work and output folders will appear in the launch folder.
6. Add your run info in `/projappl/${PROJECT}/nextflow_assembly/nextflow_run_log.txt`

```shell
sbatch nextflow_sbatch_start.sh \
-i input_folder \
-o output_folder \
-w work_folder \
-p profile_id \
-a "other_arguments"
```

Example:
```shell
sbatch nextflow_sbatch_start.sh \
-i /scratch/${PROJECT}/raw_reads \
-o /scratch/${PROJECT}/nextflow/results \
-w /scratch/${PROJECT}/nextflow/work \
-p Aplate,lumi \
-a "--busco_lineage basidiomycota_odb12 --samplesheet /scratch/${PROJECT}/raw_reads/samplesheet.tsv"
```

#### Continue failed/aborted run

> [!WARNING]
> If you used custom launch folder as described above, make sure you resume from the same folder, otherwise the cache will be wrong and pipeline will restart instead of resuming.

To resume do this:

1. **`cd` to folder from where you've launched the failed run**
2. If needed, adjust resources in `_resume.sh`
2. Launch pipeline as follows. Input `-i` and values of `-w`, `-p`, `-a` should not change between the failed run and the resuming one. Output `-o` can be changed. Use `-r` only if you need to continue from any other run but the latest. 

```shell
sbatch nextflow_sbatch2_resume.sh \
-i input_folder \
-o output_folder \
-w work_folder \
-p profile_id \
-a "other_arguments" \
-r run_id
```

Example:
```shell
sbatch nextflow_sbatch_resume.sh \
-i /scratch/${PROJECT}/raw_reads \
-o /scratch/${PROJECT}/nextflow/results \
-w /scratch/${PROJECT}/nextflow/work \
-p Aplate,lumi \
-a "--busco_lineage basidiomycota_odb12 --samplesheet /scratch/${PROJECT}/raw_reads/samplesheet.tsv" \
-r exotic_mahavira
```


<details>
<summary>Instructions for older sbatch files (removed)</summary>

Note: older sbatch files were removed from repo.

#### New run

Since projappl storage is very limited, we have to specify output and work directory in scratch. `profile_id` is needed to provide plate-specific arguments; for valid values of `profile_id`, see names of top-level closures in `profile {}` block in `*.config` file(s).

Usage: 
```sbatch **nextflow_sbatch_*start.sh** input_folder output_folder work_folder profile_id```

Example: 
```shell
sbatch nextflow_sbatch_start.sh \
/scratch/${PROJECT}/raw_reads \
/scratch/${PROJECT}/nextflow/results \
/scratch/${PROJECT}/nextflow/work \
Bplate
```

#### Continue aborted run

Use `*_resume.sh` files. Make sure to specify the same `work_folder` as in the aborted run, otherwise the run will just restart. For `*_resume.sh` files it is also possible to select from which run to continue by specifying any of its IDs in `resume_run_id`, the easiest of them to find is mnemonic name shown in `[]` after launch, e.g. `Launching 'full_assembly.nf' [exotic_mahavira]`. If wou just want to resume from the last run, leave `resume_run_id` empty. If you do want to use `resume_run_id`, then all arguments before it must not be empty. 

Usage: `sbatch **nextflow_sbatch_*resume.sh** input_folder output_folder work_folder profile_id resume_run_id`

Example: 
```shell
sbatch nextflow_sbatch_resume.sh \
/scratch/${PROJECT}/raw_reads \
/scratch/${PROJECT}/nextflow/results \
/scratch/${PROJECT}/nextflow/work \
Bplate \
exotic_mahavira
```
</details>

### Development

[Harshil alignment](https://nf-co.re/docs/developing/documentation/harshil-alignment) is not strictly endorsed.

Current approach is to keep runtime free of downloads, either DBs or software (e.g., no runtime pulls of wave containers or BUSCO DBs) - they have to be tested and operational prior to the start.

For testing modifications and future development, pipeline can be run in a stub mode when it creates the structure of output and "touches" the tools, but doesn't do any real work. It's very useful because it reveal majority of small errors without wasting resources.
It's tailored to interactive session, but can also be run on test partition or locally. 

Example (LUMI):

```sh
srun --account=${PROJECT} --partition=small --nodes=1 --ntasks=1 --cpus-per-task=2 --time=04:00:00 --mem=10G --pty $SHELL

module load LUMI/25.09 partition/C Local-CSC

module load nextflow

nextflow run full_assembly.nf --input_dir test_data/ -stub-run -profile stub
```

### Known issues

* Version file contains multiple lines for the same tool.
* Not all versions are collected yet.
* GetOrganelle output naming is not human-friendly, but difficult to "prettify".