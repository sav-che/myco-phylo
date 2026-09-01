process BUSCO {
    tag "${meta.id}"
    label 'process_medium'

    module 'busco'

    input:
    tuple val(meta), path(fasta)
    val lineage

    output:
    tuple val(meta), path("*/*/short_summary.txt"), emit: summary_txt
    tuple val(meta), path("*/*/short_summary.json"), emit: summary_json, optional: true
    tuple val(meta), path("*/*/full_table.tsv"), emit: full_table, optional: true
    tuple val(meta), path("*/*/missing_busco_list.tsv"), emit: missing, optional: true
    tuple val(meta), path("*/*/busco_sequences"), emit: sequences, optional: true
    tuple val(meta), path("*/*/hmmer_output*"), emit: hmmer, optional: true
    tuple val(meta), path("*/*/miniprot_output"), emit: miniprot, optional: true
    tuple val(meta), path("*/*/blast_output"), emit: blast, optional: true
    tuple val(meta), path("*/*/augustus_output"), emit: augustus, optional: true
    tuple val(meta), path("*/logs"), emit: logs, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Set Augustus config path 
    export AUGUSTUS_CONFIG_PATH=${params.augustus_config_path}

    # Run BUSCO
    busco \\
        -i "${fasta}" \\
        -o "${prefix}" \\
        -m genome \\
        -l ${lineage} \\
        --cpu ${task.cpus} \\
        ${args}

    # Remove temp folders and files
    rm -rf ./*/tmp # miniprot
    rm -rf ./*/blast_db # augustus
    rm -rf ./*/*/miniprot_output/ref.mpi
    rm -rf ./*/*/blast_output/sequences

    # Compress what `busco --tar` didn't, and remove originals
    MINIPROT_DIR=\$(find -path */miniprot_output -type d)

    if [ -d \${MINIPROT_DIR}/translated_proteins ]; then
        tar -czf \${MINIPROT_DIR}/translated_proteins.tar.gz \\
        -C \${MINIPROT_DIR} translated_proteins \\
        --remove-files
    fi

    # Same for Augustus
    AUGUSTUS_DIR=\$(find -path */augustus_output -type d)
    
    if [ -d \${AUGUSTUS_DIR}/extracted_proteins ]; then
        tar -czf \${AUGUSTUS_DIR}/extracted_proteins.tar.gz \\
        -C \${AUGUSTUS_DIR} extracted_proteins \\
        --remove-files
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        busco: \$(busco --version 2>&1 | sed 's/BUSCO //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p ${prefix}/run_lineage
    touch ${prefix}/run_lineage/short_summary.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        busco: \$(busco --version 2>&1 | sed 's/BUSCO //g')
    END_VERSIONS
    """
}