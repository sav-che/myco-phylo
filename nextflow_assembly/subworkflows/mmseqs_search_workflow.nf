#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// Import modules
include { MMSEQS_SEARCH } from '../modules/local/mmseqs_search.nf'
include { MMSEQS_REPORT } from '../modules/local/mmseqs_report.nf'

workflow WF_MMSEQS_SEARCH {
    take:
    query_ch // channel: [ val(meta), path(fasta) ]
    target_ch // channel: [ path(target_db_files) ]

    main:
    // Global search (all queries vs a single database)
    MMSEQS_SEARCH(
        query_ch,
        target_ch 
    )

    // Report for the search
    MMSEQS_REPORT(
        MMSEQS_SEARCH.out.top300_tsv
    )

    emit:
    // versions = all_versions
    top300_tsv = MMSEQS_SEARCH.out.top300_tsv
    top1_fasta = MMSEQS_SEARCH.out.top1_fasta
    top5_report = MMSEQS_REPORT.out.top5_report
    versions = MMSEQS_SEARCH.out.versions
}