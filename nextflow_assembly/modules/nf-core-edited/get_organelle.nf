process GET_ORGANELLE {
    tag "$meta.id"
    label 'process_high'
    module 'getorganelle'

    input:
    tuple val(meta), path(fastq)
    // tuple val(organelle_type), path(db)  // getOrganelle has a database and config file

    // TODO: output log
    output:
    tuple val(meta), path ("result/*{fungus_nr,fungus_mt}*.fasta"), emit: fasta_all
    tuple val(meta), path ("result/*fungus_nr*.fasta"), emit: fasta_nr, optional: true
    tuple val(meta), path ("result/*fungus_mt*.fasta"), emit: fasta_mt, optional: true
    tuple val(meta), path ("result/*extend*.csv"), emit: csv, optional: true 
    // TODO: when resume will be of no concern, change "result/*extend*.fastg" (2 files!) to "result/*extend-*.fastg" (1 file) and fix output{out_get_organelle_graph...} accordingly
    tuple val(meta), path ("result/*extend*.fastg"), emit: graph, optional: true
    path ("versions.yml"), emit: versions, optional: true

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // TODO: separate mt and nr searches into 2 GO runs (multioganelle mode is said to be not as efficient)
    """
    get_organelle_from_reads.py \
        $args \
        --prefix ${prefix}. \
        -o 'result' \
        -t ${task.cpus} \
        -1 ${fastq[0]} \
        -2 ${fastq[1]}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        getorganelle: \$(get_organelle_from_reads.py --version | sed 's/^GetOrganelle v//g' )
    END_VERSIONS
    """
    
    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p result
    touch "result/${prefix}.fungus_nr.fasta"
    touch "result/${prefix}.fungus_mt.fasta"
    touch "result/${prefix}.extend.csv"
    touch "result/${prefix}.extend.fastg"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        getorganelle: \$(get_organelle_from_reads.py --version | sed 's/^GetOrganelle v//g' )
    END_VERSIONS
    """
}