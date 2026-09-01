process KRAKENTOOLS_KREPORT2KRONA {
    tag "$meta.id"
    label 'process_small'
    
    module 'biokit'
    
    input:
    tuple val(meta), path(kreport)
    
    output:
    tuple val(meta), path("*.html"), emit: html
    path "versions.yml", emit: versions
    
    when:
    task.ext.when == null || task.ext.when
    
    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
  
    # Create Krona chart
    ktImportTaxonomy \\
        -o ${prefix}.krona.html \\
        ${kreport} \\
        ${args}
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ktImportTaxonomy: \$(ktImportTaxonomy 2>&1 | sed -n '2p' | grep -o 'KronaTools [0-9.]*' | awk '{print \$2}' || echo "version unknown")
    END_VERSIONS
    """
    
    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def VERSION = '1.2'
    """
    touch ${prefix}.krona.html
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ktImportTaxonomy: ${VERSION}
    END_VERSIONS
    """
}