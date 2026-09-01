#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// Import modules
// Note: NRMT means "nrDNA and mitochondria"
include { FASTP } from './modules/nf-core-edited/fastp'
include { KRAKEN2 } from './modules/nf-core-edited/kraken2'
include { KRAKENTOOLS_KREPORT2KRONA } from './modules/nf-core-edited/kreport2krona'
include { 
    SPADES as SPADES_MAIN; 
    SPADES as SPADES_NO_NRMT
    } from './modules/nf-core-edited/spades'
include { 
    BWA_MAPPING as BWA_MAIN; 
    BWA_MAPPING as BWA_NRMT
    } from './modules/local/bwa_mapping'
include { GET_ORGANELLE } from './modules/nf-core-edited/get_organelle.nf'
include { BUSCO as BUSCO_GET_ORGANELLE } from './modules/nf-core-edited/busco'
include { FASTAS_FOR_MAP } from './modules/local/fastas_for_map.nf'
include { ITSX as ITSX_GET_ORGANELLE } from './modules/local/itsx.nf'
include { FILTER_READS as FILTER_NRMT } from './modules/local/filter_reads.nf'
// include { MULTIQC } from './modules/nf-core-edited/multiqc.nf'

// Import subworkflows
include { 
    WF_QC as WF_QC_MAIN; 
    WF_QC as WF_QC_NO_NRMT
    } from './subworkflows/qc_workflow.nf'
include { 
    WF_MMSEQS_SEARCH as WF_MMSEQS_SEARCH_GET_ORG;
    WF_MMSEQS_SEARCH as WF_MMSEQS_SEARCH_ITSX_GET_ORG
    } from './subworkflows/mmseqs_search_workflow.nf'
include { WF_FCS } from './subworkflows/fcs_workflow.nf'

workflow {
    main:
    // Validate required parameters
    assert params.input_dir : 'Please provide an input directory with --input_dir'

    // Prepare clean labels and append them to data
    // If samplesheet is not provided, use automated truncation
    // If plate profile used, sample_name_parts are tailored to it
    // If plate profile not used, will keep text up to the 1st `_`
    // If sample_name_parts set to 0, keeps the entire name up to _R1
    if (params.samplesheet == null) {
        input_ch = channel
            .fromFilePairs("${params.input_dir}/${params.pattern}", checkIfExists: true)
            .map { sample_id, reads ->
            def meta = [:]
            
            // Cleaner output name: use specified # of the raw file name pars
            if (params.sample_name_parts > 0) {
                meta.id = sample_id.tokenize('_')[0..(params.sample_name_parts - 1)].join('_')
            } else {
                meta.id = sample_id  // For keeping full name
            }

            meta.single_end = false
            return [meta, reads]
            }
    }
    else {
        // Create channel for metadata
        // Expects 2 TAB-separated columns: filename-without-_R1-R2, pretty-label
        meta_ch = channel
            .fromPath(params.samplesheet, checkIfExists: true)
            .splitCsv(header: false, sep: '\t')

        // Validate: check for empty or whitespace-filled cells
        // The rest of validation is on .join(... failOnDuplicate: true, failOnMismatch: true)
        meta_ch
            .flatten()
            .filter{ name -> name ==~ /| +/ }
            .map{ error 'Error: empty cells in the sample sheet' }

        // Create input channel from paired-end files and join metadata
        input_ch = channel
            .fromFilePairs("${params.input_dir}/${params.pattern}", checkIfExists: true)
            .join(meta_ch, by: [0], failOnDuplicate: true, failOnMismatch: true)
            .map { _basename, reads, label ->
                def meta = [:]
                meta.id = label
                meta.single_end = false
                return [meta, reads]
            } 
    }

    // meta_ch checks below probably are not needed:
    // .join(... failOnDuplicate: true, failOnMismatch: true) should take care of that
/*
    // Check if columns separated 
    (meta_ch
        .map( c -> c[0] )
        .count()
    - 
    meta_ch
        .map( c -> c[1] )
        .count())
    .map( i -> i == 0 ?: error('Error: different number of records in columns 1 & 2 of the sample sheet. Check for broken separators') )

    // Check if all values in column 1 are unique.
    (meta_ch
        .map( c -> c[0] )
        .unique()
        .count()
    - 
    meta_ch
        .countLines())
    .map( i -> i == 0 ?: error('Error: duplicate values in column 1 of the sample sheet') )

    // Check if all values in column 2 are unique 
    (meta_ch
        .map( c -> c[1] )
        .unique()
        .count()
    - 
    meta_ch
        .countLines())
    .map( i -> i == 0 ?: error('Error: duplicate values in column 2 of the sample sheet. Error may be caused by broken separators') )
*/

    // Create input channel for MMseqs reference DB
    mmseqs_ref_ch = channel
        .fromPath(params.mmseqs_target + "*", checkIfExists: true)
        .collect()

    // fscgx_db_preloaded_ch = channel.fromPath(params.fcs_gx_db_stage_dir).view()

    // Create empty channels for FASTP optional inputs
    adapter_fasta = []
    discard_trimmed_pass = false
    save_trimmed_fail = false
    save_merged = false
    
    // Run FASTP for quality control and trimming
    FASTP(
        input_ch,
        adapter_fasta,
        discard_trimmed_pass,
        save_trimmed_fail,
        save_merged
    )
    
    // Run Kraken2 on trimmed reads
    KRAKEN2(
        FASTP.out.reads,
        params.kraken2_db,
        params.save_kraken_fastqs,
        params.save_kraken_assignments
    )
    
    // Convert Kraken2 reports to Krona format
    KRAKENTOOLS_KREPORT2KRONA(
        KRAKEN2.out.report
    )
    
    // Run GetOrganelle (mito & nrDNA) on trimmed reads
    GET_ORGANELLE(
        FASTP.out.reads
    )

    // SUBWORKFLOW - MMseqs2 search on total getOrganelle output
    WF_MMSEQS_SEARCH_GET_ORG(
        GET_ORGANELLE.out.fasta_all,
        mmseqs_ref_ch
    )

    // Extract ITS for taxonomy annotation
    ITSX_GET_ORGANELLE(
        GET_ORGANELLE.out.fasta_nr
    )

    // SUBWORKFLOW - MMseqs2 search on post-ITSx getOrganelle output
    WF_MMSEQS_SEARCH_ITSX_GET_ORG(
        ITSX_GET_ORGANELLE.out.fasta_all,
        mmseqs_ref_ch
    )

    // For downstream mapping, concatenate fastas and simplify headers
    FASTAS_FOR_MAP(
        GET_ORGANELLE.out.fasta_all
    )

    // BUSCO on GetOrganelle output
    BUSCO_GET_ORGANELLE(
        FASTAS_FOR_MAP.out.fasta_nrmt,
        params.busco_lineage
    )
    
    // Join outputs using genome as key
    bwa_nrmt_input_ch = KRAKEN2.out.unclassified_reads_fastq
        .join(FASTAS_FOR_MAP.out.fasta_nrmt)

    // Map reads to getOrganelle results
    BWA_NRMT(
        bwa_nrmt_input_ch
    )

    // Join outputs using genome as key
    filter_nrmt_input_ch = KRAKEN2.out.unclassified_reads_fastq
        .join(BWA_NRMT.out.bam)

    // Remove getOrganelle-mapped reads
    FILTER_NRMT(
        filter_nrmt_input_ch
    )

    // Empty channel for SPAdes yaml config
    yml_file = []  

    // Assembly with SPAdes using reads without nrDNA and mitochondria
    SPADES_NO_NRMT(
        FILTER_NRMT.out.cleaned,
        yml_file
    )

    // SUBWORKFLOW - Several genome QC programs 
    WF_QC_NO_NRMT (
        KRAKEN2.out.unclassified_reads_fastq,
        SPADES_NO_NRMT.out.contigs,
        SPADES_NO_NRMT.out.scaffolds,
        mmseqs_ref_ch
    )

    // Get genomes that failed in getOrganelle
    get_organelle_failed_ch = KRAKEN2.out.unclassified_reads_fastq
        .join(GET_ORGANELLE.out.fasta_all, remainder: true)
        .filter { i -> i[2] == null
        }
        .map { i ->
            return [i[0], i[1]]
        } 

    // Run SPAdes on all reads, either on every genome (if requested), or only when getOrganelle failed
    if (params.spades_on_all_reads == true) {
        spades_main_input_ch = KRAKEN2.out.unclassified_reads_fastq
    } else {
        spades_main_input_ch = get_organelle_failed_ch
    }

    // TODO: reuses yml_file from before - check if this is ok 
    SPADES_MAIN(
        spades_main_input_ch,
        yml_file
    )

    // Join outputs using genome as key
    bwa_main_input_ch = KRAKEN2.out.unclassified_reads_fastq
        .join(SPADES_MAIN.out.scaffolds)

    // Map unclassified reads back to the assembled scaffolds
    BWA_MAIN(
        bwa_main_input_ch
    )

    // SUBWORKFLOW - Several genome QC programs 
    WF_QC_MAIN (
        KRAKEN2.out.unclassified_reads_fastq,
        SPADES_MAIN.out.contigs,
        SPADES_MAIN.out.scaffolds,
        mmseqs_ref_ch
    )

    // SUBWORKFLOW - FCS-GX
    if (params.fcs_enable == true) {
        WF_FCS(
            SPADES_NO_NRMT.out.scaffolds.mix(SPADES_MAIN.out.scaffolds)
        )
    } else {
        // This is a hack to create WF_FCS.out. `publish:` needs it 
        WF_FCS(
            channel.empty()
        )
    }

/*    
    // TODO: finish this
    // Prepare MultiQC inputs, empty if not used
    multiqc_files = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.collect()
        )
    multiqc_config = []
    extra_multiqc_config = []
    multiqc_logo = []
    replace_names = []
    sample_names = []

    // Run MultiQC
    MULTIQC (    
        multiqc_files,
        multiqc_config,
        extra_multiqc_config,
        multiqc_logo,
        replace_names,
        sample_names
    )
*/

    // Collect all outputs
    // All must be assignments (x=y)
    publish:
    // Collect all versions
    // TODO: add SQLite
    out_all_versions = channel.empty()
        .mix(
            FASTP.out.versions,
            KRAKEN2.out.versions,
            KRAKENTOOLS_KREPORT2KRONA.out.versions,
            SPADES_MAIN.out.versions,
            BWA_MAIN.out.versions,
            GET_ORGANELLE.out.versions,
            WF_QC_MAIN.out.versions,
            WF_FCS.out.versions
        )
        .collectFile(
            name: 'software_versions.yml'
        )

    out_fastp = channel.empty()
        .mix(
            FASTP.out.html,
            FASTP.out.json,
            FASTP.out.reads
        )

    out_kraken = channel.empty()
        .mix(
            KRAKEN2.out.report,
            KRAKEN2.out.classified_reads_fastq, 
            KRAKEN2.out.unclassified_reads_fastq, 
            KRAKENTOOLS_KREPORT2KRONA.out.html
        )
    
    out_spades_main = channel.empty()
        .mix(
            SPADES_MAIN.out.contigs,
            SPADES_MAIN.out.scaffolds,
            SPADES_MAIN.out.gfa,
            SPADES_MAIN.out.assembly_graph_with_scaffolds,
            SPADES_MAIN.out.assembly_graph_after_simplification,
            SPADES_MAIN.out.warnings,
            SPADES_MAIN.out.log
        )
            
    out_quast_main = channel.empty()
        .mix(
            WF_QC_MAIN.out.quast_results,
            WF_QC_MAIN.out.quast_tsv
        )

    out_busco_get_organelle = channel.empty()
        .mix(
            BUSCO_GET_ORGANELLE.out.summary_txt,
            BUSCO_GET_ORGANELLE.out.summary_json,
            BUSCO_GET_ORGANELLE.out.full_table,
            BUSCO_GET_ORGANELLE.out.missing,
            BUSCO_GET_ORGANELLE.out.sequences,
            BUSCO_GET_ORGANELLE.out.logs
        )

    out_busco_main = channel.empty()
        .mix(
            WF_QC_MAIN.out.busco_summary_txt,
            WF_QC_MAIN.out.busco_summary_json,
            WF_QC_MAIN.out.busco_full_table,
            WF_QC_MAIN.out.busco_missing,
            WF_QC_MAIN.out.busco_sequences,
            WF_QC_MAIN.out.busco_logs
        )

    out_mmseqs_main = channel.empty()
        .mix(
            WF_QC_MAIN.out.mmseqs_on_all_top300_tsv,
            WF_QC_MAIN.out.mmseqs_on_all_top5_report
        )

    out_itsx_mmseqs_main = WF_QC_MAIN.out.itsx

    out_mmseqs_itsx_mmseqs_main = channel.empty()
        .mix(
            WF_QC_MAIN.out.mmseqs_on_itsx_top300_tsv,
            WF_QC_MAIN.out.mmseqs_on_itsx_top5_report
        )

    out_fastk_main = channel.empty()
        .mix(
            WF_QC_MAIN.out.fastk_hist,
            WF_QC_MAIN.out.fastk_ktab,
            WF_QC_MAIN.out.fastk_prof
        )

    out_merquryfk_main = channel.empty()
        .mix(
            WF_QC_MAIN.out.merquryfk_stats,
            WF_QC_MAIN.out.merquryfk_bed,
            WF_QC_MAIN.out.merquryfk_assembly_qv,
            WF_QC_MAIN.out.merquryfk_qv,
            WF_QC_MAIN.out.merquryfk_images
        )

    out_bwa_main = channel.empty()
        .mix(
            BWA_MAIN.out.bam,
            BWA_MAIN.out.bai,
            BWA_MAIN.out.stats
        )
    
    out_get_organelle_nr = GET_ORGANELLE.out.fasta_nr

    out_get_organelle_mt = GET_ORGANELLE.out.fasta_mt

    out_get_organelle_csv = GET_ORGANELLE.out.csv

    out_get_organelle_graph = GET_ORGANELLE.out.graph

    out_itsx_get_organelle = ITSX_GET_ORGANELLE.out.fasta_all

    out_bwa_nrmt = channel.empty()
        .mix(
            BWA_NRMT.out.bam,
            BWA_NRMT.out.bai,
            BWA_NRMT.out.stats
        )

    out_reads_no_nrmt = FILTER_NRMT.out.cleaned

    out_spades_no_nrmt = channel.empty()
        .mix(
            SPADES_NO_NRMT.out.contigs,
            SPADES_NO_NRMT.out.scaffolds,
            SPADES_NO_NRMT.out.gfa,
            SPADES_NO_NRMT.out.assembly_graph_with_scaffolds,
            SPADES_NO_NRMT.out.assembly_graph_after_simplification,
            SPADES_NO_NRMT.out.warnings,
            SPADES_NO_NRMT.out.log
        )

    out_mmseqs_get_organelle = channel.empty()
        .mix(
            WF_MMSEQS_SEARCH_GET_ORG.out.top300_tsv,
            WF_MMSEQS_SEARCH_GET_ORG.out.top5_report
        )

    out_mmseqs_itsx_get_organelle = channel.empty()
        .mix(
            WF_MMSEQS_SEARCH_ITSX_GET_ORG.out.top300_tsv,
            WF_MMSEQS_SEARCH_ITSX_GET_ORG.out.top5_report
        )

    out_quast_no_nrmt = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.quast_results,
            WF_QC_NO_NRMT.out.quast_tsv
        )

    out_busco_no_nrmt = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.busco_summary_txt,
            WF_QC_NO_NRMT.out.busco_summary_json,
            WF_QC_NO_NRMT.out.busco_full_table,
            WF_QC_NO_NRMT.out.busco_missing,
            WF_QC_NO_NRMT.out.busco_sequences,
            WF_QC_NO_NRMT.out.busco_logs
        )

    out_mmseqs_no_nrmt = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.mmseqs_on_all_top300_tsv,
            WF_QC_NO_NRMT.out.mmseqs_on_all_top5_report
        )

    out_itsx_mmseqs_no_nrmt = WF_QC_NO_NRMT.out.itsx

    out_mmseqs_itsx_mmseqs_no_nrmt = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.mmseqs_on_itsx_top300_tsv,
            WF_QC_NO_NRMT.out.mmseqs_on_itsx_top5_report
        )

    out_fastk_no_nrmt = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.fastk_hist,
            WF_QC_NO_NRMT.out.fastk_ktab,
            WF_QC_NO_NRMT.out.fastk_prof
        )

    out_merquryfk_no_nrmt = channel.empty()
        .mix(
            WF_QC_NO_NRMT.out.merquryfk_stats,
            WF_QC_NO_NRMT.out.merquryfk_bed,
            WF_QC_NO_NRMT.out.merquryfk_assembly_qv,
            WF_QC_NO_NRMT.out.merquryfk_qv,
            WF_QC_NO_NRMT.out.merquryfk_images
        )

    out_fcsgx = channel.empty()
        .mix(
            WF_FCS.out.fcsgx_report,
            WF_FCS.out.taxonomy_report,
            WF_FCS.out.summary
        )

    // Workflow completion message
    // TBA: update/annotate output tree
    onComplete:
        log.info """
        ==================== PIPELINE COMPLETE =====================
        Pipeline completed at: ${workflow.complete}
        Execution status: ${workflow.success ? 'ok' : 'fail'}
        Results directory: ${params.outputDir}
        Outputs generated per genome:
        ├── assembly_all_reads
        │   ├── busco
        │   ├── bwa_mapping
        │   ├── quast
        │   ├── spades
        │   ├── spades_mmseqs
        │   ├── spades_mmseqs_itsx
        │   └── spades_mmseqs_itsx_mmseqs
        ├── assembly_no_nrDNA-mito
        │   ├── busco
        │   ├── kraken
        │   ├── quast
        │   ├── spades
        │   ├── spades_mmseqs
        │   ├── spades_mmseqs_itsx
        │   └── spades_mmseqs_itsx_mmseqs
        ├── assembly_nrDNA-mito
        │   ├── bwa_mapping
        │   ├── get_organelle
        │   ├── get_organelle_itsx
        │   ├── get_organelle_itsx_mmseqs
        │   └── get_organelle_mmseqs
        ├── fastp
        └── kraken
        ============================================================
        """.stripIndent()
}

// 'output' and 'publish:' must have the same channels 
output {
    out_all_versions { path {'pipeline_info'} }
    out_fastp { path {i -> "${i[0].id}/fastp"} }
    out_kraken { path {i -> "${i[0].id}/kraken"} }
    out_spades_main { path {i -> "${i[0].id}/assembly_all_reads/spades"} }
    out_quast_main { path {i -> "${i[0].id}/assembly_all_reads/quast"} }
    out_busco_main { path {i -> i[1] >> "${i[0].id}/assembly_all_reads/busco/${i[1].getName()}"} }
    out_mmseqs_main { path {i -> "${i[0].id}/assembly_all_reads/spades_mmseqs"} }
    out_itsx_mmseqs_main { path {i -> "${i[0].id}/assembly_all_reads/spades_mmseqs_itsx"} }
    out_mmseqs_itsx_mmseqs_main { path {i -> "${i[0].id}/assembly_all_reads/spades_mmseqs_itsx_mmseqs"} }
    out_bwa_main { path {i -> "${i[0].id}/assembly_all_reads/bwa_mapping"} }
    // These are nice but don't work, because sometimes there are >1 paths and fastas:   
    // out_get_organelle_nr { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/${i[0].id}.getorganelle.nrDNA.fasta"} }
    // out_get_organelle_mt { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/${i[0].id}.getorganelle.mito.fasta"} }
    out_get_organelle_nr { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/"} }
    out_get_organelle_mt { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/"} }
    out_get_organelle_csv { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/${i[0].id}.getorganelle.loci.csv"} }
    out_get_organelle_graph { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/"} }
    out_busco_get_organelle { path {i -> i[1] >> "${i[0].id}/assembly_nrDNA-mito/get_organelle/busco/${i[1].getName()}"} }
    out_itsx_get_organelle { path {i -> "${i[0].id}/assembly_nrDNA-mito/get_organelle_itsx"} }
    out_mmseqs_get_organelle { path {i -> "${i[0].id}/assembly_nrDNA-mito/get_organelle_mmseqs"} }
    out_mmseqs_itsx_get_organelle { path {i -> "${i[0].id}/assembly_nrDNA-mito/get_organelle_itsx_mmseqs"} }
    out_fastk_main { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/merquryfk"} }
    out_merquryfk_main { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/merquryfk"} }
    out_bwa_nrmt { path {i -> "${i[0].id}/assembly_nrDNA-mito/bwa_mapping"} }
    out_reads_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/kraken"} }
    out_spades_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/spades"} }
    out_quast_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/quast"} }
    out_busco_no_nrmt { path {i -> i[1] >> "${i[0].id}/assembly_no_nrDNA-mito/busco/${i[1].getName()}"} }
    out_mmseqs_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/spades_mmseqs"} }
    out_itsx_mmseqs_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/spades_mmseqs_itsx"} }
    out_mmseqs_itsx_mmseqs_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/spades_mmseqs_itsx_mmseqs"} }
    out_fastk_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/merquryfk"} }
    out_merquryfk_no_nrmt { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/merquryfk"} }
    out_fcsgx { path {i -> "${i[0].id}/assembly_no_nrDNA-mito/fcs-gx"} }
}
