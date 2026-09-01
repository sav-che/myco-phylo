process FCSGX_DB_UNLOAD {

    cache false

    input:
    val all_results // Dummy, to cleanup only when all results are ready

    script:
    def job_fast_memory = params.fast_memory
    """
        echo "...Removing FCS-GX DB stage folder: rm -rf ${job_fast_memory}/gxdb"
        rm -rf "${job_fast_memory}/gxdb"
    """
}

