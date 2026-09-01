// Workflow inspired by https://github.com/nf-core/genomeqc/blob/dev/subworkflows/local/decontamination.nf

include { FCSGX_RUNGX } from '../modules/nf-core-edited/fcsgx_rungx.nf'
include { FCSGX_DB_UNLOAD } from '../modules/local/fcsgx_db_unload.nf'

workflow WF_FCS {
    take:
    fasta_ch // channel: [ val(meta), [ fasta ] ]

    main:
    versions_ch = channel.empty()

    // Load DB to fast memory and run FCS-GX
    // Tested only in non-parallel mode (maxForks = 1)
    // Parallel will need better check on DB integrity to avoid parallel DB uploads
    FCSGX_RUNGX (
        fasta_ch.collect(), // To start only when all inputs are ready and not to hug memory in advance
        fasta_ch
    )

    // Remove DB from fast memory, only when all results are ready
    FCSGX_DB_UNLOAD (
        FCSGX_RUNGX.out.fcsgx_report.collect()
    )

    versions_ch = versions_ch.mix(FCSGX_RUNGX.out.versions.first())

    emit:
    fcsgx_report = FCSGX_RUNGX.out.fcsgx_report // channel: [ val(meta), [ fcsgx_report ] ]
    taxonomy_report = FCSGX_RUNGX.out.taxonomy_report // channel: [ val(meta), [ taxonomy_report ] ]
    summary = FCSGX_RUNGX.out.summary // channel: [ val(meta), [ summary ] ]
    versions = versions_ch // channel: [ versions.yml ]
}

