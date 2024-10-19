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
        result_cloud_reader = cloud_reader_task.result_cloud_reader,
        docker_version = pharmcat_version,
        max_concurrent_processes = max_concurrent_processes,
        max_memory = max_memory,
  }
  
  # call cloud_writer_task {
  #   input:
  #     results = pipeline_task.results,
  # }


  output {
    # File results = pipeline_task.results
    File result_cloud_reader = cloud_reader_task.result_cloud_reader
  }
}

task cloud_reader_task {
  input {
    String? input_directory
    Int max_concurrent_processes
    String max_memory
  }

  command <<<
    set -e -x -o pipefail

    # Create folders
    mkdir -p files/input_directory

    # Create log file
    log_file="files/log.txt"
    touch $log_file
    echo "-----------------------" >> $log_file
    echo "Start Cloud Reader Task" >> $log_file
    echo "-----------------------" >> $log_file

    # Check gsutil
    gsutil --version >> $log_file

    # Process the Directory Input [ files_directory ]
    # -----------------------------------------------
    if [[ ~{true='true' false='false' defined(input_directory)} == "true" ]]; then
      echo "Start to Read from Files Directory: ~{input_directory}" >> $log_file
      # Check if input_directory is a Google Storage
      if [[ "~{input_directory}" == gs://* ]]; then
        echo "Copying all files from directory: ~{input_directory}" >> $log_file
        # List all the files in the directory
        gsutil ls "~{input_directory}/*" >> $log_file
        # Copy all the files from the directory to the local folder
        gsutil cp "~{input_directory}/*" files/input_directory/ >> $log_file
        echo "All files from ~{input_directory} have been copied to files/input_directory/" >> $log_file
      else
        echo "ERROR: The directory path is not a valid gs:// URL. Skipping file copy." >> $log_file
      fi
    else
      echo "The files_directory input type wasn't defined" >> $log_file
    fi


    # Prepare the folder structure to process in next task
    if [[ $(ls files/input_directory | wc -l) -gt 0 ]]; then
      file_count=$(ls files/input_directory/* | wc -l)
      echo "Number of files copied: $file_count" >> $log_file
      echo "End of Cloud Reader Task" >> $log_file
      tar -czvf files.tar.gz files
    else
      echo "No files to compress" >> $log_file
      tar -czvf files.tar.gz files
    fi

  >>>

  output {
    File result_cloud_reader = "files.tar.gz"
  }

  runtime {
    docker: "ricoandre/cloud-tools:latest"
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task pipeline_task {
  input {
    # Environment Settings
    String docker_version
    Int max_concurrent_processes
    String max_memory
    Boolean delete_intermediate_files = false

    # Diretory from cloud_reader_task
    File result_cloud_reader

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
    tar -xzvf ~{result_cloud_reader}

    # Start log file
    log_file="files/log.txt"
    echo " " >> $log_file
    echo "---------------------------" >> $log_file
    echo "Start VCF Preprocessor Task" >> $log_file
    echo "---------------------------" >> $log_file

    # Common arguments
    arg=" -o files/Results"

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

    # The $single_vcf_mode will control the model to run
    # Exemplo de comando final
    # cmd="python3 /path/to/pharmcat_pipeline.py $arg"
    # echo "Running: $cmd" >> files/log.txt
    # eval $cmd

    VCFs_list="files/VCFs_list.txt"
    touch $VCFs_list

    echo "Run PharmCAT Pipeline" >> $log_file

    # Option 1: User add on VCF or TSV file in the vcf_file inputx
    if [[ -n "~{vcf_file}" && -f ~{vcf_file} ]]; then
      # Copy to input_directory because host all vcf files in tsv or outside.calls
      cp ~{vcf_file} files/input_directory
      echo "Processing as a single mode VCF or TSV" >> $log_file
      # Prepare command sintax
      cmd="pharmcat_pipeline files/input_directory/$(basename ~{vcf_file}) $args"
      echo "Running command: $cmd" >> $log_file
      eval $cmd

    # Option 2: None VCF or TSV input. Check directory content to process
    elif [[ -z "~{vcf_file}" ]]; then
      echo "Processing all individual VCF files in the directory" >> $log_file
      
      ls files/VCFs_inputs/*.vcf.* >> $VCFs_list  # Create list with all vcf in the directory

      # # Run all vcf files in the diretory individually
      # for vcf_file in $(cat $VCFs_list); do
      #   echo "Processing individual VCF file: $vcf_file" >> $log_file
      #   cmd="pharmcat_pipeline $vcf_file $args"
      #   echo "Running command: $cmd" >> $log_file
      #   eval $cmd
      # done

    else
      echo "No VCF or list of VCFs provided. Exiting." >> $log_file
      exit 1
    fi

    # Run the command
    echo "Pharmcat_pipeline finished" >> $log_file

    # Package the entire 'files' directory and create a tar.gz file
    tar -czvf results.tar.gz files
  >>>

  output {
      File results = "results.tar.gz"
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}" 
    memory: max_memory
    cpu: max_concurrent_processes
  }
}


# task cloud_writer_task {
#   input {
#     File? result_vcf_preprocessor
#     String? results_directory
#   }

#   command <<<
#     set -e -x -o pipefail

#     # Extract the compressed file from a_cloud_reader_task
#     tar -xzvf ~{result_vcf_preprocessor}

#     # Start log file
#     log_file="files/log.txt"
#     echo " " >> $log_file
#     echo "-----------------------" >> $log_file
#     echo "Start Cloud Writer Task" >> $log_file
#     echo "-----------------------" >> $log_file

#     # Ensure gsutil is available in this environment
#     if ! command -v gsutil &> /dev/null; then
#       echo "ERROR: gsutil not found. Please ensure gsutil is available." >> $log_file
#       exit 1
#     fi

#     # Save Results in directory defined by the user
#     echo "Copying results to ~{results_directory}" >> $log_file

#     # TODO - Add other cloud directories 
#     if [[ ~{results_directory} == gs://* ]]; then
#       # Copying individual result files
#       gsutil cp Results/* "~{results_directory}/" >> $log_file
#       # Copying the pre_processor tar.gz as well
#       gsutil cp ~{result_vcf_preprocessor} ~{results_directory}/ >> $log_file
#     else
#       echo "ERROR: Unsupported storage destination. Only gs:// is supported in this task." >> $log_file
#       exit 1
#     fi

#     echo "Cloud Writer Task completed successfully." >> $log_file
#   >>>

#   output {
#     File log = "files/log.txt"
#   }

#   runtime {
#     docker: "ricoandre/cloud-tools:latest"
#     memory: "4G"
#     cpu: 1
#   }
# }