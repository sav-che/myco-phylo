## Download GenBank specimen metadata for many accessions using Entrez Direct

Installation and documentation for EDirect https://www.ncbi.nlm.nih.gov/books/NBK179288/

`esearch -query` accepts a regular GenBank search string in quotation marks.
To (almost) stop query expansion (= strict search), use `[WORD]` field after each query word. 
More info on fields: https://www.ncbi.nlm.nih.gov/books/NBK49540/
Example query (=contents of genbank_query.txt): `(holotype[WORD] OR neotype[WORD]) AND ((Cerinomyces borealis[ORGN]) OR (Tremella torta[ORGN]))`

INSDSeq_comment added because RefSeq sequences store accession ID of origin sequence in this field and nowhere else.

"QUERY FAILURE" message is normal and indicates that not all items were found.
"ERROR: Missing -query argument" or "Missing -db argument" likely indicate that query is too long. 

Specify input and output files:
```sh
ENTREZ_QUERY=$(< "genbank_query.txt")
ENTREZ_RESULT="genbank_records.tsv"
```

Search GenBank through EDirect:
```sh
esearch -db nuccore -query "$ENTREZ_QUERY" | \
efetch -format gbc | \
sed s/\&#xa\;/" "/ | \
xtract -head accession comment keyword organism type_material specimen_voucher isolate isolation_source clone bio_material tissue_type culture_collection strain geo_loc_name lat_lon altitude collection_date collected_by identified_by note marker other-seqids\
    -pattern INSDSeq -def "-" -sep "|" -element INSDSeq_primary-accession INSDSeq_comment INSDKeyword \
    -group INSDFeature -if INSDFeature_key -equals source -pfx "\n" \
        -block INSDQualifier -if INSDQualifier_name -equals organism -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals organism -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals type_material -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals type_material -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals specimen_voucher -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals specimen_voucher -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals isolate -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals isolate -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals isolation_source -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals isolation_source -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals clone -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals clone -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals bio_material -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals bio_material -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals tissue_type -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals tissue_type -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals culture_collection -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals culture_collection -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals strain -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals strain -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals geo_loc_name -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals geo_loc_name -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals lat_lon -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals lat_lon -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals altitude -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals altitude -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals collection_date -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals collection_date -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals collected_by -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals collected_by -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals identified_by -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals identified_by -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals note -sfx "\t" -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals note -sfx "\t" -lbl "\-" \
    -group INSDFeature -if INSDFeature_key -equals misc_RNA -clr -lbl "#misc_RNA:" \
        -block INSDQualifier -if INSDQualifier_name -equals note -deq " " -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals note -deq " " -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals product -deq " / " -sfx " " -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals product -deq " / " -sfx " " -lbl "\-" \
    -group INSDFeature -if INSDFeature_key -equals rRNA -clr -lbl "#rRNA:" \
        -block INSDQualifier -if INSDQualifier_name -equals product -deq " " -sfx " " -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals product -deq " " -sfx " " -lbl "\-" \
    -group INSDFeature -if INSDFeature_key -equals gene -clr -lbl "#gene:" \
        -block INSDQualifier -if INSDQualifier_name -equals gene -deq " " -sfx " " -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals gene -deq " " -sfx " " -lbl "\-" \
    -group INSDFeature -if INSDFeature_key -equals CDS -clr -lbl "#CDS:" \
        -block INSDQualifier -if INSDQualifier_name -equals gene -deq " " -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals gene -deq " " -lbl "\-" \
        -block INSDQualifier -if INSDQualifier_name -equals product -deq " / " -sfx " " -element INSDQualifier_value \
        -block INSDFeature -unless INSDQualifier_name -equals product -deq " / " -sfx " " -lbl "\-" \
    -group INSDSeq_other-seqids -sep "|" -element INSDSeqid \
> "$ENTREZ_RESULT"
```