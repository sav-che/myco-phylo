// modules/local/mmseqs_report.nf

process MMSEQS_REPORT {
    tag "${meta.id}"
    label 'process_small'
    module 'sqlite'
    
    input:
    tuple val(meta), path(input_tsv)
    
    output:
    tuple val(meta), path("*-mito.tsv"), emit: top5_report

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def columns = task.ext.args
    """
    echo "...Preparing taxonomy columns"

    # Prepare taxonomy columns. In UNITE/EUKARYOME results, taxonomy should be
    # separated from general target_id and broken down into separate per-rank columns.

    # If needed, adjust col to the number of the column with taxonomy
    awk -v col=4 'BEGIN{FS=OFS="\\t"} {if (NR>1) {gsub("\\\\([^)(]+\\\\)", "", \$col);
    {if(match(\$col, ".+;s__")){gsub(";s__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    {if(match(\$col, ".+;g__")){gsub(";g__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    {if(match(\$col, ".+;f__")){gsub(";f__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    {if(match(\$col, ".+;o__")){gsub(";o__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    {if(match(\$col, ".+;c__")){gsub(";c__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    {if(match(\$col, ".+;p__")){gsub(";p__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    {if(match(\$col, ".+[|;]k__")){gsub(";k__", "\\t", \$col)} else {sub("\$", "\\tLOST_DATA", \$col)}};
    gsub("unclassified", "", \$col);
    gsub("[^\\t]+incertae_sedis", "", \$col);}
    sub("\\ttarget\\t", "\\ttarget_id\\ttarget_k\\ttarget_p\\ttarget_c\\ttarget_o\\ttarget_f\\ttarget_g\\ttarget_s\\t");
    print}' ${input_tsv} > mmseqs_tax-sep.tsv

    echo "...Populating database"

    # Import to SQLite table
    sqlite3 -batch mmseqs_tax-sep.sqlite3 <<EOSQL
    .mode tabs
    .import mmseqs_tax-sep.tsv main
    EOSQL

    echo "...Compiling report"

    # Main SQLite block: 
    sqlite3 -batch mmseqs_tax-sep.sqlite3 <<EOSQL
    .mode tabs
    .headers on

    create view output as
    -- Reorient range coordinates and sort end coords 
    with 
    rcoords as (
    select 
        min(cast(qstart as integer), cast(qend as integer)) as rstart,
        max(cast(qstart as integer), cast(qend as integer)) as rend,
        max(max(cast(qstart as integer), cast(qend as integer))) over win_max_local as max_local,
        *
    from main
    window win_max_local as (partition by qset, "query" order by min(cast(qstart as integer), cast(qend as integer)) range between unbounded preceding and current row)
    order by qset, "query", min(cast(qstart as integer), cast(qend as integer))
    ),
    -- Mark starts of ranges
    rchanges as (
    select
        case (sign((lag(max_local,1) over win_4lag)-rstart))
            when -1 then 1
            when 0 then 1
            else 0
            end
        as rchange,
        *
    from rcoords
    window win_4lag as (partition by qset,"query" order by rstart)
    ),
    -- Assign ID to ranges
    ranges as (
    select
        sum (rchange) over win_4lag2 as range_id,
        *
    from rchanges
    window win_4lag2 as (partition by qset,"query" order by rstart)
    ),
    -- Add summaries of next 4 rows to each row
    top as (
    select
        *,
        -- Lump top 5
        group_concat (target_p, ' | ')
            over win_top5
            as top_5_target_taxa_p,
        group_concat (target_g, ' | ')
            over win_top5
            as top_5_target_taxa_g,
        -- 2nd best            
        nth_value(target_p || ' ' || target_f || ': ' || target_g || ' ' || target_s, 2)
            over win_top5
            as target_2,
        nth_value(pident, 2)
            over win_top5
            as pident_2,
        nth_value(alnlen, 2)
            over win_top5
            as alnlen_2,
        nth_value(evalue, 2)
            over win_top5
            as evalue_2,
        -- 3rd best
        nth_value(target_p || ' ' || target_f || ': ' || target_g || ' ' || target_s, 3)
            over win_top5
            as target_3,
        nth_value(pident, 3)
            over win_top5
            as pident_3,
        nth_value(alnlen, 3)
            over win_top5
            as alnlen_3,
        nth_value(evalue, 3)
            over win_top5
            as evalue_3,
        -- 4th best                          
        nth_value(target_p || ' ' || target_f || ': ' || target_g || ' ' || target_s, 4)
            over win_top5
            as target_4,
        nth_value(pident, 4)
            over win_top5
            as pident_4,
        nth_value(alnlen, 4)
            over win_top5
            as alnlen_4,
        nth_value(evalue, 4)
            over win_top5
            as evalue_4,
        -- 5th best                          
        nth_value(target_p || ' ' || target_f || ': ' || target_g || ' ' || target_s, 5)
            over win_top5
            as target_5,
        nth_value(pident, 5)
            over win_top5
            as pident_5,
        nth_value(alnlen, 5)
            over win_top5
            as alnlen_5,
        nth_value(evalue, 5)
            over win_top5
            as evalue_5
    from ranges
    window win_top5 as (partition by qset, "query", range_id order by cast(bits as integer) desc rows between current row and 4 following)
    order by qset, "query", range_id, cast(bits as integer) desc
    )
    -- Collapse to the top row per range
    select 
        *,
        case when cast(qend as integer)>cast(qstart as integer) then 'plus' else 'minus' end as strand_top_hit,
        count("query") as total_hits,
        count("query") over (partition by qset, "query") as n_ranges
    from top
    group by qset, "query", range_id
    -- order by qset, "query", range_id
    order by qset, target_k, target_p, target_c, target_o, target_f, target_g, cast(bits as integer) desc
    ;

    -- Stage output file for the next query
    .once "${prefix}.mmseqs.top5_with-mito.tsv"

    select ${columns}
    from output
    ;

    -- Stage output file for the next query
    .once "${prefix}.mmseqs.top5_no-mito.tsv"

    select ${columns}
    from output
    where target_k not like '%_mitochondrion%'
    ;

    .quit
    EOSQL

    # Remove the database
    rm -f mmseqs_tax-sep.sqlite3

    echo "...Padding results"

    # Pad each filename change with empty line
    awk -i inplace '{print (NR>2 && \$1!=p ? s : "") \$0; p=\$1; s=ORS}' "${prefix}.mmseqs.top5_with-mito.tsv"
    awk -i inplace '{print (NR>2 && \$1!=p ? s : "") \$0; p=\$1; s=ORS}' "${prefix}.mmseqs.top5_no-mito.tsv"

    echo -e "...All done"
    """

    stub:
    def columns = task.ext.args
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo $columns | cat > "${prefix}.mmseqs.top5_with-mito.tsv"
    echo $columns | cat > "${prefix}.mmseqs.top5_no-mito.tsv"
    """
}