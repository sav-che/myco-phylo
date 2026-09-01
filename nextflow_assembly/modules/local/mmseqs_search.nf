// modules/local/mmseqs_search.nf

process MMSEQS_SEARCH {
    tag "${meta.id}"
    label 'process_high'
    module 'mmseqs2'

    input:
    tuple val(meta), path(query_db)
    path target_db
    
    output:
    tuple val(meta), path ("*.mmseqs.top300.tsv"), emit: top300_tsv
    tuple val(meta), path ("*.mmseqs.top1.qaln-qseq.fas"), emit: top1_fasta
    tuple val(meta), path ("*.mmseqs.tar.gz"), emit: raw_compressed
    path "versions.yml", emit: versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // Get ref DB basename. Must be a better solution, but this works
    def target_db_name = target_db.first().baseName.replaceFirst(/_h$/, '')
    """
    echo -e "...Making MMseqs query DB\\n"

    # Prepare query DB from all input files
    mmseqs createdb \\
    --dbtype 2 \\
    --createdb-mode 0 \\
    --shuffle 0 \\
    --write-lookup 1 \\
    ${query_db} \\
    mmseqs_query_db

    echo -e "\\n...Searching query DB against target DB\\n"

    # Main search
    mmseqs search \\
    --threads ${task.cpus} \\
    ${args} \\
    mmseqs_query_db \\
    ${target_db_name} \\
    mmseqs_search \\
    tmp

    echo -e "\\n...Slimming results to top 300 lines per query sequence\\n"

    # Extract top 300 lines per query sequence
    mmseqs filterdb \\
    --threads ${task.cpus} \\
    --extract-lines 300 \\
    mmseqs_search \\
    mmseqs_search_top300

    echo -e "\\n...Converting result to tabular format\\n"

    # Convert to tabular format
    mmseqs convertalis \\
    --search-type 3 \\
    --format-mode 4 \\
    --format-output qset,query,tset,target,pident,alnlen,qcov,evalue,bits,qlen,tlen,mismatch,gapopen,qstart,qend,tstart,tend \\
    --threads ${task.cpus} \\
    mmseqs_query_db \\
    ${target_db_name} \\
    mmseqs_search_top300 \\
    "${prefix}.mmseqs.top300.tsv"

    echo -e "\\n...Transforming aligned portions of queries into fasta\\n"

    # Extract top 1 line per query sequence
    mmseqs filterdb \\
    --threads ${task.cpus} \\
    --extract-lines 1 \\
    mmseqs_search \\
    mmseqs_search_top1

    # Convert to tabular format
    mmseqs convertalis \\
    --search-type 3 \\
    --format-mode 0 \\
    --format-output query,qaln,qseq \\
    --threads ${task.cpus} \\
    mmseqs_query_db \\
    ${target_db_name} \\
    mmseqs_search_top1 \\
    mmseqs_search_top1.tsv

    # Transform tsv to fasta
    # In theory, MMseqs can do it internally, but I gave up trying

    # Write qaln - only aligned region
    awk 'BEGIN{FS="\\t"} {OFS="\\n"} {
        gsub("^", ">", \$1);
        gsub("[- ]", "", \$2);
        print \$1 "_aligned" OFS \$2}' mmseqs_search_top1.tsv > "${prefix}.mmseqs.top1.qaln-qseq.fas"

    # Write-append qseq - full query sequence
    awk 'BEGIN{FS="\\t"} {OFS="\\n"} {
        gsub("^", ">", \$1);
        print \$1 OFS \$3}' mmseqs_search_top1.tsv >> "${prefix}.mmseqs.top1.qaln-qseq.fas"

    echo -e "\\n...Compressing raw results\\n"
    
    # Compress raw result DB
    mmseqs compress mmseqs_search mmseqs_search_compress

    # Archive compressed result DB
    tar -czvf "${prefix}.mmseqs.tar.gz" mmseqs_search_compress*

    echo "...MMseqs2 search finished"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mmseqs: \$(mmseqs | grep 'Version' | sed 's/MMseqs2 Version: //')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def target_db_name = target_db.first().baseName.replaceFirst(/_h$/, '')
    """
    echo "Query files: ${query_db}"
    echo "Target DB basename: ${target_db_name}"
    echo "Target DB files: ${target_db}"
    touch "mmseqs_query_db"
    touch "mmseqs_search"
    touch "mmseqs_search_compress"
    touch "${prefix}.mmseqs.tar.gz"
    touch "${prefix}.mmseqs.top300"
    touch "${prefix}.mmseqs.top300.tsv"
    touch "${prefix}.mmseqs.top1.qaln-qseq.fas"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mmseqs: \$(mmseqs | grep 'Version' | sed 's/MMseqs2 Version: //')
    END_VERSIONS
    """
    }