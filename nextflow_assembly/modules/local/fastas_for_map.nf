process FASTAS_FOR_MAP {
    tag "$meta.id"
    label 'process_small'
    module 'seqkit'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.nrmt.fasta", arity: '1'), emit: fasta_nrmt

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Concatenate fastas, shorten names (original can be very long), and make them unique
    seqkit replace -w 0 -p '^(.{20}).+' -r '\$1' ${fasta} | seqkit rename -1 -w 0  > ${prefix}.nrmt.fasta
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.nrmt.fasta"
    """
}

