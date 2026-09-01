// modules/local/bwa_mapping.nf

process BWA_MAPPING {
    tag "$meta.id"
    label 'process_medium'
    module 'biokit:bwa'
    
    input:
    tuple val(meta), path(reads), path(reference)
    // tuple val(meta), path(reads)
    // tuple val(meta_ref), path(reference)
    
    output:
    tuple val(meta), path("*.bam"), emit: bam, optional: true
    tuple val(meta), path("*.bai"), emit: bai, optional: true
    tuple val(meta), path("*_samtools_statistics.txt"), emit: stats, optional: true
    path "versions.yml", emit: versions
    
    when:
    task.ext.when == null || task.ext.when
    
    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // def _reference_basename = reference.baseName
    """
    # Index the reference genome (only if index files don't exist)
    if [ ! -f "${reference}.bwt" ]; then
        bwa index -a bwtsw $reference
    fi
 
    # Run the alignment
    bwa mem \\
        -t $task.cpus \\
        $args \\
        $reference \\
        $reads \\
        | samtools view -@ "${task.cpus}" -b \\
        | samtools sort -@ "${task.cpus}" -o "${prefix}_aln_sorted.bam"

    # Index the BAM file
    samtools index "${prefix}_aln_sorted.bam"

    # Generate statistics
    samtools flagstat "${prefix}_aln_sorted.bam" > "${prefix}_samtools_statistics.txt"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bwa: \$(bwa 2>&1 | grep 'Version' | sed 's/Version: //')
        samtools: \$(samtools --version 2>&1 | head -n1 | sed 's/samtools //')
    END_VERSIONS
    """
    
    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}_aln_sorted.bam"
    touch "${prefix}_aln_sorted.bam.bai"
    touch "${prefix}_samtools_statistics.txt"
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bwa: \$(bwa 2>&1 | grep 'Version' | sed 's/Version: //')
        samtools: \$(samtools --version 2>&1 | head -n1 | sed 's/samtools //')
    END_VERSIONS
    """
}