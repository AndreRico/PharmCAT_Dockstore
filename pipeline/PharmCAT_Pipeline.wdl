version 1.0

workflow pharmcat_pipeline {
  input {
    # File? input_file  # Simple VCF or TSV file
    String? input_directory  # Read all VCF from a diretory
    # String? results_directory  # Write the Results in Cloud Diretory
    
    String pharmcat_version = "2.13.0"
    Int max_concurrent_processes = 1
    String max_memory = "4G"

  }

  call cloud_reader_task {
    input:
      input_directory = input_directory,
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory
  }

  call pipeline_task {
      input:
        cloud_reader_results = cloud_reader_task.cloud_reader_results,
        docker_version = pharmcat_version,
        max_concurrent_processes = max_concurrent_processes,
        max_memory = max_memory,
  }
  
  call cloud_writer_task {
    input:
      pipeline_results = pipeline_task.pipeline_results,
  }


  output {
    # File results = pipeline_task.results
    File cloud_reader_results = cloud_reader_task.cloud_reader_results
    File pipeline_results = pipeline_task.pipeline_results
    File log = cloud_writer_task.log
  }
}

# ---------------------------------------------------------------------
# TASK 1: Cloud Reader Task
# ---------------------------------------------------------------------
task cloud_reader_task {
  input {
    String? input_directory
    Int max_concurrent_processes
    String max_memory
  }

  command <<<
    set -e -x -o pipefail

    # Create folders
    mkdir -p wf/data
    mkdir -p wf/results

    # Create log file
    log_file="wf/log.txt"
    touch $log_file
    echo "-----------------------" >> $log_file
    echo "Start Cloud Reader Task" >> $log_file
    echo "-----------------------" >> $log_file

    # Check gsutil
    gsutil --version >> $log_file

    # TODO - Check if the diretory has / at the end, delete if has.

    # Process the Directory Input [ files_directory ]
    if [[ ~{true='true' false='false' defined(input_directory)} == "true" ]]; then
      echo "Start to Read from Files Directory: ~{input_directory}" >> $log_file
      # Check if input_directory is a Google Storage
      if [[ "~{input_directory}" == gs://* ]]; then
        echo "Copying all files from directory: ~{input_directory}" >> $log_file
        # List all the files in the directory
        gsutil ls "~{input_directory}/*" >> $log_file
        # Copy all the files from the directory to the local folder
        gsutil cp "~{input_directory}/*" wf/data/ >> $log_file
        echo "All files from ~{input_directory} have been copied to wf/data/" >> $log_file
      else
        echo "ERROR: The directory path is not a valid gs:// URL. Skipping file copy." >> $log_file
      fi
    else
      echo "The files_directory input type wasn't defined" >> $log_file
    fi

    # Prepare the folder structure to process in next task
    if [[ $(ls wf/data | wc -l) -gt 0 ]]; then
      file_count=$(ls wf/data/* | wc -l)
      echo "Number of files copied: $file_count" >> $log_file
      echo "End of Cloud Reader Task" >> $log_file
      tar -czvf cloud_reader_results.tar.gz wf
    else
      echo "No files to compress" >> $log_file
      tar -czvf cloud_reader_results.tar.gz wf
    fi
  >>>

  output {
    File cloud_reader_results = "cloud_reader_results.tar.gz"
  }

  runtime {
    docker: "ricoandre/cloud-tools:latest"
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

# ---------------------------------------------------------------------
# TASK 2: Pipeline Task
# ---------------------------------------------------------------------
task pipeline_task {
  input {
    # Environment Settings
    String docker_version
    Int max_concurrent_processes
    String max_memory
    Boolean delete_intermediate_files = false

    # Diretory from cloud_reader_task
    File cloud_reader_results

    # Read single files
    File? vcf_file
    String? base_filename

    # Sample informations
    File? sample_file  # Optional file containing a list of sample IDs
    String? sample_ids  # Optional comma-separated list of sample IDs
    
    # Args to Preprocessor
    Boolean missing_to_ref = false
    Boolean no_gvcf_check = false
    Boolean retain_specific_regions = false  # Flag to retain specific genomic regions
    File? reference_regions_to_retain  # BED file specifying PGx regions to retain

    # Args to Named Allele Matcher
    Boolean run_matcher = false  # Flag to run only Named Allele Matcher
    Boolean matcher_all_results = false
    Boolean matcher_save_html = false
    String research_mode = ""
    
    # Args to Phonopyter
    Boolean run_phenotype = false  # Flag to run only Phenotype
    
    # Args to Reporter
    Boolean run_reporter = false  # Flag to run only Reporter
    String reporter_sources = ""
    Boolean reporter_extended = false
    Boolean reporter_save_json = false
  }

  command <<<
    set -e -x -o pipefail
  
    # Extract the compressed file from a_cloud_reader_task
    tar -xzvf ~{cloud_reader_results}

    # Start log file
    log_file="wf/log.txt"
    echo " " >> $log_file
    echo "---------------------------" >> $log_file
    echo "Start VCF Preprocessor Task" >> $log_file
    echo "---------------------------" >> $log_file

    # Create list file to keep VCFs to process
    list="wf/list.txt"
    touch $list

    # Common arguments
    arg=" -o wf/results"

    # Sample inputs
    if [ ! -z "$sample_file" ]; then
      arg+=" -S $sample_file"
    fi

    if [ ! -z "$sample_ids" ]; then
      arg+=" -s $sample_ids"
    fi

    # Preprocessor arguments
    if [ "$missing_to_ref" == "true" ]; then
      arg+=" -0"  # --missing-to-ref
    fi

    if [ "$no_gvcf_check" == "true" ]; then
      arg+=" -G"  # --no-gvcf-check
    fi

    if [ "$retain_specific_regions" == "true" ]; then
      arg+=" -R"  # Retain specific regions
    fi

    if [ ! -z "$reference_regions_to_retain" ]; then
      arg+=" -refRegion $reference_regions_to_retain"  # Specify the BED file for regions to retain
    fi

    # Named Allele Matcher arguments
    if [ "$run_matcher" == "true" ]; then
      arg+=" -matcher"  # Run named allele matcher
    fi

    if [ "$matcher_all_results" == "true" ]; then
      arg+=" -ma"  # Return all possible diplotypes
    fi

    if [ "$matcher_save_html" == "true" ]; then
      arg+=" -matcherHtml"  # Save matcher results as HTML
    fi

    if [ ! -z "$research_mode" ]; then
      arg+=" -research $research_mode"  # Enable research mode features
    fi

    # Phenotyper arguments
    if [ "$run_phenotype" == "true" ]; then
      arg+=" -phenotyper"  # Run phenotyper independently
    fi

    # Reporter arguments
    if [ "$run_reporter" == "true" ]; then
      arg+=" -reporter"  # Run reporter independently
    fi

    if [ ! -z "$reporter_sources" ]; then
      arg+=" -rs $reporter_sources"  # Specify sources for the reporter
    fi

    if [ "$reporter_extended" == "true" ]; then
      arg+=" -re"  # Write an extended report
    fi

    if [ "$reporter_save_json" == "true" ]; then
      arg+=" -reporterJson"  # Save reporter results as JSON
    fi

    # Output and concurrency arguments
    if [ ! -z "$base_filename" ]; then
      arg+=" -bf $base_filename"  # Set base filename for output
    fi

    if [ "$delete_intermediate_files" == "true" ]; then
      arg+=" -del"  # Delete intermediate PharmCAT files
    fi

    if [ ! -z "$max_concurrent_processes" ]; then
      arg+=" -cp $max_concurrent_processes"  # Set max concurrent processes
    fi

    if [ ! -z "$max_memory" ]; then
      arg+=" -cm $max_memory"  # Set max memory
    fi

    echo "Set Common Arguments: $arg" >> $log_file

    # Mandatory argument: -vcf.
    # -------------------------
    # Path to a single VCF file or a file containing the list of VCF file paths (one per line),
    #   sorted by chromosome position. All VCF files must have the same set of samples. Use this
    #   when data for a sample has been split among multiple files (e.g. VCF files from large
    #   cohorts, such as UK Biobank). Input VCF files must at least comply with 
    #   Variant Call Format (VCF) Version >= 4.2.

    # Resolver a variável `vcf_file` fora do bloco condicional
    # Nao podemos usar a variavel `vcf_file` dentro do bloco condicional
    vcf_file="~{vcf_file}"

    # Obter a extensão do arquivo para verificar se é um arquivo de lista ou um VCF simples
    file_extension="${vcf_file##*.}"

    # option 1: User add on VCF or TSV file in the vcf_file input
    if [[ -n "$vcf_file" && -f "$vcf_file" ]]; then
      # cp ~{vcf_file} wf/data
      # echo "Processing list of VCF files as a single block from: ~{vcf_file}" >> $log_file
      # cmd="pharmcat_pipeline wf/data/$(basename ~{vcf_file}) $arg"
      # echo "Running command: $cmd" >> $log_file
      # eval $cmd

      echo "Processing list of VCF files as a single block from: ~{vcf_file}" >> $log_file

      if [[ "$file_extension" == "txt" || "$file_extension" == "tsv" ]]; then
        echo "Treatment pathway from : $vcf_file" >> $log_file

        # Copiar o arquivo de lista para a pasta interna 'wf/data'
        cp "$vcf_file" wf/data
        list_file="wf/data/$(basename "$vcf_file")"

        # Criar um novo arquivo de lista com o caminho completo 'wf/data/'
        adjusted_list="wf/data/adjusted_list.txt"
        touch $adjusted_list

        # Verificar cada linha no arquivo original e adicionar 'wf/data/' caso necessário
        while read -r line; do
          if [[ "$line" == wf/data/* ]]; then
            # Se a linha já contém 'wf/data/', adicionar diretamente
            echo "$line" >> $adjusted_list
          else
            # Caso contrário, adicionar o prefixo 'wf/data/'
            echo "wf/data/$line" >> $adjusted_list
          fi
        done < "$list_file"

        echo "Adjusted VCF list created at: $adjusted_list" >> $log_file

        # Rodar o PharmCAT com a lista ajustada
        cmd="pharmcat_pipeline $adjusted_list $arg"
        echo "Running command: $cmd" >> $log_file
        eval $cmd
      
      else
        # Caso seja um arquivo VCF simples, processá-lo diretamente
        echo "Processing single VCF file: $vcf_file" >> $log_file
        cp "$vcf_file" wf/data
        cmd="pharmcat_pipeline wf/data/$(basename "$vcf_file") $arg"
        echo "Running command: $cmd" >> $log_file
        eval $cmd
      fi


    # Option 2: None VCF or TSV input. Check directory content to process
    elif [[ -z "$vcf_file" ]]; then
      if [[ $(ls wf/data/*.vcf.* 2>/dev/null | wc -l) -gt 0 ]]; then
        echo "Processing all individual VCF files in the directory: wf/data/" >> $log_file

        VCFs_list="wf/VCFs_list.txt"
        ls wf/data/*.vcf.* > $VCFs_list

        while read -r vcf_file; do
          echo "Processing individual VCF file: $vcf_file" >> $log_file
          cmd="pharmcat_pipeline $vcf_file $arg"
          echo "Running command: $cmd" >> $log_file
          eval $cmd
        done < $VCFs_list
      else
        echo "No VCF files found in wf/data/. Exiting." >> $log_file
        exit 1
      fi

    else
      echo "No VCF or list of VCFs provided or found in directory. Exiting." >> $log_file
      exit 1
    fi


    # Run the command
    echo "Pharmcat_pipeline finished" >> $log_file

    # Package the entire 'wf' directory and create a tar.gz file
    tar -czvf pipeline_results.tar.gz wf
  >>>

  output {
      File pipeline_results = "pipeline_results.tar.gz"
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}" 
    memory: max_memory
    cpu: max_concurrent_processes
  }
}


task cloud_writer_task {
  input {
    File? pipeline_results
    String? results_directory
  }

  command <<<
    set -e -x -o pipefail

    # Extrair o arquivo compactado
    tar -xzvf ~{pipeline_results}

    # Iniciar arquivo de log
    log_file="wf/log.txt"
    echo " " >> $log_file
    echo "-----------------------" >> $log_file
    echo "Start Cloud Writer Task" >> $log_file
    echo "-----------------------" >> $log_file

    # Definir a variável results_directory como string
    results_directory="~{results_directory}"

    # Verificar se results_directory foi definido e não está vazio
    if [[ -n "$results_directory" ]]; then  
      # Verificar se gsutil está disponível neste ambiente
      if ! command -v gsutil &> /dev/null; then
        echo "ERROR: gsutil not found. Please ensure gsutil is available." >> $log_file
        exit 1
      fi

      # Salvar resultados no diretório definido pelo usuário
      echo "Copying results to $results_directory" >> $log_file

      # TODO - Adicionar suporte para outros diretórios em nuvem
      if [[ "$results_directory" == gs://* ]]; then
        # Copiar arquivos de resultados individuais
        gsutil cp wf/results/* "$results_directory/" >> $log_file
        # Copiar também o arquivo tar.gz com os resultados do pipeline
        # gsutil cp ~{pipeline_results} "$results_directory/" >> $log_file
      else
        echo "ERROR: Unsupported storage destination. Only gs:// is supported in this task." >> $log_file
        exit 1
      fi

      echo "Cloud Writer Task completed successfully." >> $log_file
    else
      echo "No results directory defined. Skipping cloud write." >> $log_file
    fi

  >>>

  output {
    File log = "wf/log.txt"
  }

  runtime {
    docker: "ricoandre/cloud-tools:latest"
    memory: "4G"
    cpu: 1
  }
}