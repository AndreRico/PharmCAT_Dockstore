version 1.0

workflow pharmcat_vcf_preprocess_workflow {
  meta {
    author: "ClinPGx"
    email: "pharmcat@pharmgkb.org"
    description: "This workflow runs the PharmCAT VCF Preprocessor to prepare a VCF file for further analysis."
  }

  input {
    File input_file  # Input file (can be a single VCF or a TSV with URLs to VCFs)
    Boolean is_tsv = false  # Determines if the input is a TSV with URLs
    Boolean single_sample_mode = false  # Whether to generate one VCF per sample
    File? sample_file  # Optional file containing a list of sample IDs
    String? sample_ids  # Optional comma-separated list of sample IDs
    String? base_filename  # Prefix for the output files
    Boolean keep_intermediate_files = false  # Whether to keep intermediate files
    Boolean missing_to_ref = false  # Add missing PGx positions as reference
    Boolean concurrent_mode = false  # Enable concurrent mode
    Int? max_concurrent_processes  # Max concurrent processes
    Boolean verbose = false  # Enable verbose output
    Boolean no_gvcf_check = false  # Bypass the check for gVCF format
    File? reference_pgx_vcf  # Custom PGx VCF for reference positions
    File? reference_genome  # Custom reference genome (GRCh38)
    Boolean retain_specific_regions = false  # Retain specific regions
    File? reference_regions_to_retain  # BED file specifying PGx regions to retain
  }

  call vcf_preprocess_unified {
    input:
      input_file = input_file,
      is_tsv = is_tsv,
      sample_file = sample_file,
      sample_ids = sample_ids,
      base_filename = base_filename,
      keep_intermediate_files = keep_intermediate_files,
      single_sample = single_sample_mode,
      missing_to_ref = missing_to_ref,
      concurrent_mode = concurrent_mode,
      max_concurrent_processes = max_concurrent_processes,
      verbose = verbose,
      no_gvcf_check = no_gvcf_check,
      reference_pgx_vcf = reference_pgx_vcf,
      reference_genome = reference_genome,
      retain_specific_regions = retain_specific_regions,
      reference_regions_to_retain = reference_regions_to_retain
  }

  output {
    Array[File] preprocessed_vcf_files = vcf_preprocess_unified.output_vcf_files
  }
}

task vcf_preprocess_unified {
  meta {
    author: "ClinPGx"
    email: "pharmcat@pharmgkb.org"
    description: "This task runs the PharmCAT VCF Preprocessor script to prepare a VCF file for PharmCAT."
  }
  
  input {
    File input_file  # Input file (either VCF or TSV with URLs)
    Boolean is_tsv = false  # Whether the input is a TSV with URLs
    File? sample_file  # Optional file with sample IDs
    String? sample_ids  # Comma-separated list of sample IDs
    String? base_filename  # Output file prefix
    Boolean keep_intermediate_files = false  # Keep intermediate files
    Boolean single_sample = false  # Generate one VCF per sample
    Boolean missing_to_ref = false  # Add missing PGx positions as reference
    Boolean concurrent_mode = false  # Enable concurrent mode
    Int? max_concurrent_processes  # Max concurrent processes
    Boolean verbose = false  # Enable verbose output
    Boolean no_gvcf_check = false  # Bypass gVCF check
    File? reference_pgx_vcf  # Custom PGx reference VCF
    File? reference_genome  # Custom reference genome (FASTA)
    Boolean retain_specific_regions = false  # Retain specific regions
    File? reference_regions_to_retain  # BED file specifying regions to retain
  }

  command <<<
    set -e -x -o pipefail

    # Create the output directory
    mkdir -p vcf_files

    # if [ "~{is_tsv}" == "true" ]; then
    #   # Download VCF files from URLs listed in the TSV
    #   while read -r url; do
    #     wget -P vcf_files $url
    #   done < ~{input_file}
    #   vcf_list=$(ls vcf_files/*)
    # else
    #   # If single VCF, copy to the local folder
    #   cp ~{input_file} vcf_files/
    #   vcf_list="vcf_files/$(basename ~{input_file})"
    # fi

    # Adicionar um ls para verificar o diretório antes de baixar arquivos
    echo "Conteúdo do diretório antes de baixar arquivos:"
    ls -l vcf_files

    if [ "~{is_tsv}" == "true" ]; then
      # Baixar os arquivos VCF listados no arquivo TSV de URLs
      tsv_path="vcf_files/downloaded_vcfs.txt"
      touch $tsv_path

      while read -r url; do
        # Baixar cada arquivo VCF
        wget -P vcf_files $url
        # Adicionar o caminho local ao novo TSV
        echo "vcf_files/$(basename $url)" >> $tsv_path
      done < ~{input_file}

      # Passar o novo TSV com os caminhos locais para o preprocessor
      vcf_list=$tsv_path
    else
      # Se for um único VCF, copiar para o diretório local
      cp ~{input_file} vcf_files/
      vcf_list="vcf_files/$(basename ~{input_file})"
    fi

    # Exibir o conteúdo de vcf_files após o download ou cópia dos arquivos
    echo "Conteúdo do diretório após o download/cópia:"
    ls -l vcf_files

    # Exibir o conteúdo de vcf_list para ver o que está sendo passado ao preprocessor
    echo "Conteúdo de vcf_list:"
    cat $vcf_list

    # Construct the command for the preprocessor
    cmd="python3 /pharmcat/pharmcat_vcf_preprocessor.py -vcf $vcf_list"
    
    # # Argumentos opcionais
    # ~{if defined(sample_file) then 'cmd=cmd + " -S " + sample_file' else ''}
    # ~{if defined(sample_ids) then 'cmd=cmd + " -s " + sample_ids' else ''}
    # ~{if defined(base_filename) then 'cmd=cmd + " -bf " + base_filename' else ''}
    # ~{if keep_intermediate_files then 'cmd=cmd + " -k "' else ''}
    # ~{if single_sample then 'cmd=cmd + " -ss "' else ''}
    # ~{if missing_to_ref then 'cmd=cmd + " -0 "' else ''}
    # ~{if concurrent_mode then 'cmd=cmd + " -c "' else ''}
    # ~{if defined(max_concurrent_processes) then 'cmd=cmd + " -cp " + max_concurrent_processes' else ''}
    # ~{if verbose then 'cmd=cmd + " -v "' else ''}
    # ~{if no_gvcf_check then 'cmd=cmd + " -G "' else ''}
    # ~{if defined(reference_pgx_vcf) then 'cmd=cmd + " -refVcf " + reference_pgx_vcf' else ''}
    # ~{if defined(reference_genome) then 'cmd=cmd + " -refFna " + reference_genome' else ''}
    # ~{if retain_specific_regions then 'cmd=cmd + " -R "' else ''}
    # ~{if defined(reference_regions_to_retain) then 'cmd=cmd + " -refRegion " + reference_regions_to_retain' else ''}

    if [ ! -z "$sample_file" ]; then
      cmd+=" -S $sample_file"
    fi

    if [ ! -z "$sample_ids" ]; then
      cmd+=" -s $sample_ids"
    fi

    if [ "$keep_intermediate_files" == "true" ]; then
      cmd+=" -k"
    fi

    if [ "$single_sample" == "true" ]; then
      cmd+=" -ss"
    fi

    if [ "$missing_to_ref" == "true" ]; then
      cmd+=" -0"
    fi

    if [ "$concurrent_mode" == "true" ]; then
      cmd+=" -c"
    fi

    if [ ! -z "$max_concurrent_processes" ]; then
      cmd+=" -cp $max_concurrent_processes"
    fi

    if [ "$verbose" == "true" ]; then
      cmd+=" -v"
    fi

    if [ "$no_gvcf_check" == "true" ]; then
      cmd+=" -G"
    fi


    # Run the command
    echo ls
    echo "Running command: $cmd"
    eval $cmd
  >>>

  output {
    Array[File] output_vcf_files = glob("vcf_files/*.vcf*")
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "4G"
    cpu: 4
  }
}
