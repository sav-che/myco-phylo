process QUAST {
    tag "$meta.id"
    label 'process_medium'
    
    module 'quast'
    
    input:
    tuple val(meta), path(consensus)
    
    output:
    tuple val(meta), path("${meta.id}")     , emit: results
    tuple val(meta), path("${meta.id}.tsv") , emit: tsv
    path "versions.yml"                     , emit: versions
    
    when:
    task.ext.when == null || task.ext.when
    
    script:
    def args = task.ext.args ?: ''
    def prefix = meta.id
    """
    quast.py \\
        --output-dir $prefix \\
        --threads $task.cpus \\
        $args \\
        ${consensus.join(' ')}
    
    ln -s ${prefix}/report.tsv ${prefix}.tsv
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        quast: \$(quast.py --version 2>&1 | grep "QUAST" | sed 's/^.*QUAST v//; s/ .*\$//')
    END_VERSIONS
    """
    
    stub:
    def prefix = meta.id
    """
    mkdir -p $prefix
    touch $prefix/report.tsv
    touch $prefix/report.html
    touch $prefix/report.txt
    touch $prefix/quast.log
    
    ln -s $prefix/report.tsv ${prefix}.tsv
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        quast: \$(quast.py --version 2>&1 | grep "QUAST" | sed 's/^.*QUAST v//; s/ .*\$//')
    END_VERSIONS
    """
}