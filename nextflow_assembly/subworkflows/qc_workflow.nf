#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// Import modules
include { QUAST } from '../modules/nf-core-edited/quast'
include { BUSCO } from '../modules/nf-core-edited/busco'
include { ITSX } from '../modules/local/itsx.nf'
include { FASTK } from '../modules/nf-core-edited/fastk.nf'
include { MERQURYFK } from '../modules/nf-core-edited/merquryfk.nf'

// Import subworkflows
include { 
    WF_MMSEQS_SEARCH as WF_MMSEQS_SEARCH_ON_ALL; 
    WF_MMSEQS_SEARCH as WF_MMSEQS_SEARCH_ON_ITSX
    } from './mmseqs_search_workflow.nf'

workflow WF_QC {
    take:
    reads_ch // channel: [ val(meta), path(reads) ]
    contigs_ch // channel: [ val(meta), path(contigs) ]
    scaffolds_ch // channel: [ val(meta), path(scaffolds) ]
    mmseqs_ref_ch // channel: [ path(target_db_files) ]

    main:
    // Quality assessment with QUAST
    // Combine contigs and scaffolds for QUAST analysis
    assembly_files = contigs_ch
        .join(scaffolds_ch, remainder: true)
        .map { meta, contigs, scaffolds ->
            def files = []
            if (contigs) files.add(contigs)
            if (scaffolds) files.add(scaffolds)
            return [meta, files]
        }
        .filter { meta, files -> files.size() > 0 }
    
    QUAST(assembly_files)

    // BUSCO assessment on scaffolds
    BUSCO(
        scaffolds_ch,
        params.busco_lineage
    )

    // Global search (all queries vs a single database)
    WF_MMSEQS_SEARCH_ON_ALL(
        scaffolds_ch,
        mmseqs_ref_ch
    )

    // Run ITSx on MMseqs output that includes
    // 1) entire node sequences that were matched by search and
    // 2) their aligned region from top1 hit
    ITSX(
        WF_MMSEQS_SEARCH_ON_ALL.out.top1_fasta
    )

    // Global search (all queries vs a single database)
    WF_MMSEQS_SEARCH_ON_ITSX(
        ITSX.out.fasta_all,
        mmseqs_ref_ch
    )

    // Count kmers for MerquryFK
    FASTK(
        reads_ch
    )

    // Prepare input for MerquryFK
    merqury_input_ch = FASTK.out.hist
        .join(FASTK.out.ktab)
        .join(scaffolds_ch)

    MERQURYFK(
        merqury_input_ch 
    )

    // Collect all versions
    // TBA: SQLite...
    all_versions = channel.empty()
        .mix(
            // FASTK.out.versions_fastk,
            // MERQURYFK.out.versions_merquryfk,
            // MERQURYFK.out.versions_r,
            QUAST.out.versions,
            BUSCO.out.versions,
            WF_MMSEQS_SEARCH_ON_ALL.out.versions
        )

    emit:
    versions = all_versions

    quast_results = QUAST.out.results
    quast_tsv = QUAST.out.tsv

    busco_summary_txt = BUSCO.out.summary_txt
    busco_summary_json = BUSCO.out.summary_json
    busco_full_table = BUSCO.out.full_table
    busco_missing = BUSCO.out.missing
    busco_sequences = BUSCO.out.sequences
    busco_logs = BUSCO.out.logs
            
    itsx = ITSX.out.fasta_all

    mmseqs_on_all_top300_tsv = WF_MMSEQS_SEARCH_ON_ALL.out.top300_tsv
    mmseqs_on_all_top5_report = WF_MMSEQS_SEARCH_ON_ALL.out.top5_report

    mmseqs_on_itsx_top300_tsv = WF_MMSEQS_SEARCH_ON_ITSX.out.top300_tsv
    mmseqs_on_itsx_top5_report = WF_MMSEQS_SEARCH_ON_ITSX.out.top5_report

    fastk_hist = FASTK.out.hist
    fastk_ktab = FASTK.out.ktab
    fastk_prof = FASTK.out.prof

    merquryfk_stats = MERQURYFK.out.stats
    merquryfk_bed = MERQURYFK.out.bed
    merquryfk_assembly_qv = MERQURYFK.out.assembly_qv
    merquryfk_qv = MERQURYFK.out.qv
    merquryfk_images = MERQURYFK.out.images

}