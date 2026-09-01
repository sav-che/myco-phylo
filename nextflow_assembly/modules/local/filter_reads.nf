process FILTER_READS {
    tag "${meta.id}"
    label 'process_medium'
    module 'seqkit'

    input:
    tuple val(meta), path(target), path(query)
    // tuple val(meta), path(target) // Reads of genome to clean
    // tuple val(meta2), path(query) // Source of reads to remove from genome, bam after BWA
    
    output:
    tuple val(meta), path("*.gz"), emit: cleaned

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Prepare a list of reads to remove
    seqkit bam \\
    --field Read \\
    --threads ${task.cpus} \\
    --prim-only \\
    ${query} \\
    2> ${prefix}.to_exclude.txt

    # Remove reads matching the exclusion list
    # R1
    seqkit grep \\
    --invert-match \\
    --pattern-file ${prefix}.to_exclude.txt \\
    --threads ${task.cpus} \\
    ${target[0]} \\
    --out-file "${prefix}_R1_cleaned.fastq.gz"

    # R2
    seqkit grep \\
    --invert-match \\
    --pattern-file ${prefix}.to_exclude.txt \\
    --threads ${task.cpus} \\
    ${target[1]} \\
    --out-file "${prefix}_R2_cleaned.fastq.gz"
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip > ${prefix}_R1_cleaned.fastq.gz
    echo "" | gzip > ${prefix}_R2_cleaned.fastq.gz 
    """
}