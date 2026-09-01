// modules/local/itsx.nf

process ITSX {
    tag "${meta.id}"
    label 'process_medium'
    module 'biokit:itsx'

    input:
    tuple val(meta), path(query)
    
    output:
    tuple val(meta), path("*.fasta"), emit: fasta_all, optional: true
    tuple val(meta), path("*{ITS1,ITS2}.fasta"), emit: fasta_nr, optional: true
    tuple val(meta), path("*full.fasta"), emit: its_full, optional: true
    tuple val(meta), path("*ITS1.fasta"), emit: its1, optional: true
    tuple val(meta), path("*ITS2.fasta"), emit: its2, optional: true

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def profiles = params.itsx_profiles
    """
    ITSx \\
    -i ${query} \\
    -o ${prefix} \\
    --cpu ${task.cpus} \\
    -p $profiles \\
    $args
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.full.fasta"
    touch "${prefix}.ITS1.fasta"
    touch "${prefix}.ITS2.fasta" 
    """
}