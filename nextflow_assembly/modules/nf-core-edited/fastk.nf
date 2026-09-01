process FASTK {
    tag "$meta.id"
    label 'process_medium'

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.hist")                      , emit: hist
    tuple val(meta), path("*.ktab*", hidden: true)       , emit: ktab
    tuple val(meta), path("*.{prof,pidx}*", hidden: true), emit: prof, optional: true
    // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    tuple val("${task.process}"), val('fastk'), eval('echo 1.2'), emit: versions_fastk, topic: versions

    script:
    def args      = task.ext.args ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def container = params.fastk_container
    """
    export SING_IMAGE="${container}"
    export SING_FLAGS=""
    
    apptainer_wrapper exec \\
    FastK \\
        $args \\
        -T$task.cpus \\
        -M${task.memory.toGiga()} \\
        -N${prefix} \\
        $reads

    find . -name '*.ktab*' -exec chmod a+r {} \\;
    """

    stub:
    def args       = task.ext.args ?: ''
    def prefix     = task.ext.prefix ?: "${meta.id}"
    def touch_ktab = args.contains('-t') ? "touch ${prefix}.ktab .${prefix}.ktab.1" : ''
    def touch_prof = args.contains('-p') ? "touch ${prefix}.prof .${prefix}.pidx.1" : ''
    """
    touch ${prefix}.hist
    $touch_ktab
    $touch_prof

    echo \\
    "FastK \\
        $args \\
        -T$task.cpus \\
        -M${task.memory.toGiga()} \\
        -N${prefix}_fk \\
        $reads"
    """
}