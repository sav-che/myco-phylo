process FCSGX_RUNGX {
    tag "$meta.id"
    label 'process_high'

    input:
    val all_inputs // Dummy, to start only when all inputs are ready and not to hug memory in advance
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.fcs_gx_report.txt"), emit: fcsgx_report
    tuple val(meta), path("*.taxonomy.rpt"), emit: taxonomy_report
    tuple val(meta), path("*.summary.txt"), emit: summary
    tuple val(meta), path("*.hits.tsv.gz"), emit: hits, optional: true
    path "versions.yml", emit: versions

    script:
    def taxid = params.fcs_gx_taxid
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def db = params.fcs_gx_db_source_dir
    def job_fast_memory = params.fast_memory
    def container = params.fcs_gx_container
    """
    if [ ! -d "${job_fast_memory}/gxdb" ]; then
        mkdir "${job_fast_memory}/gxdb"
        for i in "${db}/*" ; do 
            rsync -av \$i "${job_fast_memory}/gxdb/" &
        done
        echo "...Stage folder did not exist: created, DB staged"
        echo "...Contents of stage folder ${job_fast_memory}/gxdb :"
        ls -lh "${job_fast_memory}/gxdb"
    else
        echo "...Stage folder exists: doing nothing"
        echo "...Contents of stage folder ${job_fast_memory}/gxdb :"
        ls -lh "${job_fast_memory}/gxdb"
    fi

    export SING_IMAGE="${container}"
    export SING_FLAGS=""
    export GX_NUM_CORES=${task.cpus}
    apptainer_wrapper exec /app/bin/run_gx \\
        --fasta ${fasta} \\
        --gx-db "${job_fast_memory}/gxdb" \\
        --tax-id ${taxid} \\
        --generate-logfile true \\
        --out-basename ${prefix} \\
        --out-dir . \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fcsgx: \$( apptainer_wrapper exec /app/bin/gx --help | sed '/build/!d; s/.*:v//; s/-.*//' )
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def container = params.fcs_gx_container
    """
    touch ${prefix}.fcs_gx_report.txt
    touch ${prefix}.taxonomy.rpt
    touch ${prefix}.summary.txt
    echo "" | gzip > ${prefix}.hits.tsv.gz

    export SING_IMAGE="${container}"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fcsgx: \$( apptainer_wrapper exec /app/bin/gx --help | sed '/build/!d; s/.*:v//; s/-.*//' )
    END_VERSIONS
    """
}
