process MERQURYFK {
    tag "$meta.id"
    label 'process_medium'

    input:
    tuple val(meta) , path(fastk_hist), path(fastk_ktab), path(assembly)

    output:
    tuple val(meta), path("*.completeness.stats"), emit: stats
    tuple val(meta), path("*.*_only.bed")        , emit: bed
    tuple val(meta), path("*.*.qv")              , emit: assembly_qv
    tuple val(meta), path("*.qv")                , emit: qv
    tuple val(meta), path("*.{pdf,png}")         , emit: images, optional: true
    // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    tuple val("${task.process}"), val('merquryfk'), eval('echo 1.2'), emit: versions_merquryfk, topic: versions
    tuple val("${task.process}"), val('R'), eval('R --version | sed "1!d; s/.*version //; s/ .*//"'), emit: versions_r, topic: versions

    script:
    def args        = task.ext.args ?: ''
    def prefix      = task.ext.prefix ?: "${meta.id}"
    def fk_ktab     = fastk_ktab ? "${fastk_ktab.find { path -> path.toString().endsWith(".ktab") }}" : ''
    def container   = params.merquryfk_container
    """
    export SING_IMAGE="${container}"
    export SING_FLAGS=""

    apptainer_wrapper exec \\
    MerquryFK \\
        $args \\
        -T$task.cpus \\
        ${fk_ktab} \\
        $assembly \\
        $prefix
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.completeness.stats
    touch ${prefix}.qv
    touch ${prefix}._.qv
    touch ${prefix}._only.bed
    """
}