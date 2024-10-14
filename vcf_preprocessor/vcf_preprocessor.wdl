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
    Array[File]? vcf_input_files  # Lista de arquivos VCF, caso seja necessário múltiplos VCFs
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
      vcf_input_files = vcf_input_files,
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
    File input_file  # Arquivo de entrada, VCF ou TSV
    Boolean is_tsv = false  # Se for TSV com URLs
    Array[File]? vcf_input_files  # Lista de arquivos VCF a serem processados
    File? sample_file  # Arquivo opcional com os IDs de samples
    String? sample_ids  # Lista de samples
    String? base_filename  # Prefixo para arquivos de saída
    Boolean keep_intermediate_files = false  # Manter arquivos intermediários
    Boolean single_sample = false  # Um VCF por sample
    Boolean missing_to_ref = false  # Adicionar posições PGx como referência
    Boolean concurrent_mode = false  # Ativar modo concorrente
    Int? max_concurrent_processes  # Máximo de processos concorrentes
    Boolean verbose = false  # Saída detalhada
    Boolean no_gvcf_check = false  # Ignorar verificação de gVCF
    File? reference_pgx_vcf  # VCF de referência customizado
    File? reference_genome  # Genoma de referência customizado
    Boolean retain_specific_regions = false  # Manter regiões específicas
    File? reference_regions_to_retain  # Arquivo BED com regiões específicas
  }

  command <<<
    set -e -x -o pipefail

    # Criar o diretório de saída
    mkdir -p vcf_files  # Usando vcf_files apenas como diretório temporário

    if [ "~{is_tsv}" == "true" ]; then
      # Criar uma lista de arquivos VCF usando o input TSV
      tsv_path="vcf_files/downloaded_vcfs.tsv"
      touch $tsv_path

      while read -r file; do
        # Adicionar os arquivos VCF da lista
        echo "~{vcf_input_files} $(basename $file)" >> $tsv_path
      done < ~{input_file}

      vcf_list=$tsv_path
    else
      # Se for um único VCF, copiá-lo diretamente
      cp ~{input_file} vcf_files/
      vcf_list="vcf_files/$(basename ~{input_file})"
    fi

    # Exibir o conteúdo da lista de VCFs
    echo "Conteúdo do vcf_list:"
    cat $vcf_list

    # Montar o comando de execução
    cmd="python3 /pharmcat/pharmcat_vcf_preprocessor.py -vcf $vcf_list"

    if [ "$single_sample" == "true" ]; then
      cmd+=" -ss"
    fi

    if [ "$keep_intermediate_files" == "true" ]; then
      cmd+=" -k"
    fi

    # Executar o comando
    echo "Executando o comando: $cmd"
    eval $cmd
  >>>

  output {
    Array[File] output_vcf_files = glob("vcf_files/*.vcf*")  # Mantém o uso de vcf_files como diretório temporário
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "4G"
    cpu: 4
  }
}
