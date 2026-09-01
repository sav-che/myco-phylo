### Supporting scripts for nextflow assembly output

## Location: /projappl/${PROJECT}/supporting_for_nextflow_assembly/
Before usage please upload the following python environment:
`module load biopythontools`

## Version file cleaning: versions_cleaning.py
Usage: 
`python versions_cleaning.py -i ../path_to_results/pipeline_info/software_versions.yml -o ../path_to_results/pipeline_info/cleaned_versions.yml`

## Quast merging: merge_quast_reports.py
Usage:
`python merge_quast_reports.py -i /path_to_results/quast/ -o /path_to_results/quast_merged.tsv`

## Busco summary: busco_logs_to_table.py
Usage:
`python busco_logs_to_table.py -i /path_to_results/busco -o /path_to_results/busco_summary.tsv`

## Note
Those scripts were written by ChatGpt 
