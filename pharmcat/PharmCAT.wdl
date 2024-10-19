version 1.0

workflow pharmcat {
  input {
    File? files_list  # Optional input file containing list of URLs
    Array[File]? files_local  # Optional array of files
    String? files_directory  # Read all VCF from a diretory
    String? results_directory  # Write the Results in Cloud Diretory
    String pharmcat_version = "2.13.0"
    Int max_concurrent_processes = 1
    String max_memory = "4G"

    Boolean run_vcf_preprocessor = true  # Flag to control VCF Preprocessor
    Boolean run_named_allele_matcher = true  # Flag to control Named Allele Matcher
    Boolean run_phenotype = true  # Flag to control Phenotype
    Boolean run_report = true  # Flag to control Report generation
  }

  call cloud_reader_task {
    input:
      files_list = files_list,
      files_local = files_local,
      files_directory = files_directory,
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory
  }

  # Subtasks controladas por flags
  if (run_vcf_preprocessor) {
    call vcf_preprocessor_task {
      input:
        result_cloud_reader = cloud_reader_task.result_cloud_reader,
        docker_version = pharmcat_version,
        max_concurrent_processes = max_concurrent_processes,
        max_memory = max_memory,
    }
  }

  if (run_named_allele_matcher) {
    call named_allele_matcher_task {
      input:
        result_vcf_preprocessor = vcf_preprocessor_task.result_vcf_preprocessor,
        docker_version = pharmcat_version,
        max_concurrent_processes = max_concurrent_processes,
        max_memory = max_memory,
    }
  }

if (run_phenotype) {
    call phenotype_task {
      input:
        result_named_allele_matcher = named_allele_matcher_task.result_named_allele_matcher,
        docker_version = pharmcat_version,
        max_concurrent_processes = max_concurrent_processes,
        max_memory = max_memory,
    }
  }

if (run_reporter) {
    call reporter_task {
      input:
        result_phenotyper = named_allele_matcher_task.result_phenotyper,
        docker_version = pharmcat_version,
        max_concurrent_processes = max_concurrent_processes,
        max_memory = max_memory,
    }
  }

  if (defined(results_directory) && results_directory != "") {
    call cloud_writer_task {
      input:
        result_vcf_preprocessor = pharmcat_task.result_vcf_preprocessor,
        results_directory = results_directory
    }
  }

  output {
    # File log = task03_cloud_writer_task.log
  }
}

task cloud_reader_task {
  input {
    File? files_list
    Array[File]? files_local
    String? files_directory
    Int max_concurrent_processes
    String max_memory
  }

  command <<<
    set -e -x -o pipefail

    # Create folders
    mkdir -p files/VCFs_inputs

    # Create log file
    log_file="files/log.txt"
    touch $log_file
    echo "-----------------------" >> $log_file
    echo "Start Cloud Reader Task" >> $log_file
    echo "-----------------------" >> $log_file

    # Create the txt file
    VCFs_list="files/VCFs_list.txt"
    touch $VCFs_list

    # Check gsutil
    gsutil --version >> $log_file


    # Process the Directory Input [ files_directory ]
    # -----------------------------------------------
    if [[ ~{true='true' false='false' defined(files_directory)} == "true" ]]; then
      echo "Start to Read from Files Directory: ~{files_directory}" >> $log_file
      # Check if files_directory is a Google Storage
      if [[ "~{files_directory}" == gs://* ]]; then
        echo "Copying all VCF files from directory: ~{files_directory}" >> $log_file
        # List all the VCF files in the directory
        gsutil ls "~{files_directory}/*.vcf.*" >> $log_file
        # Copy all the VCF files from the directory to the local folder
        gsutil cp "~{files_directory}/*.vcf.*" files/VCFs_inputs/ >> $log_file
        # Add all copied files to the VCFs list file
        ls files/VCFs_inputs/*.vcf.* >> files/VCFs_list.txt
        echo "All VCF files from ~{files_directory} have been copied to files/VCFs_inputs/" >> $log_file
      
      # The files_directory no works in local paths. We can not mount in runtime. 
      # TODO - Add other cloud directories 
      # Handle unsupported directory formats
      else
        echo "ERROR: The directory path is not a valid gs:// URL. Skipping file copy." >> $log_file
      fi
    else
      echo "The files_directory input type wasn't defined" >> $log_file
    fi

    # Process the List File [ files_list ]
    # ------------------------------------
    if [[ -n "~{files_list}" ]]; then
      echo "Start to Read from Files List" >> $log_file
      
      for url in $(cat ~{files_list}); do
        if [[ $url == http* ]]; then
          echo "-- Get $url by wget" >> $log_file
          wget -P files/VCFs_inputs $url --verbose
        
        elif [[ $url == gs://* ]]; then
          echo "-- Get $url by gsutil" >> $log_file
          gsutil cp $url files/VCFs_inputs/
      
        # TODO - Add other cloud directories 
        else
          echo "-- URL formant not support: $url" >> $log_file
        fi
      done
    fi

    # Process the Local File in Array [ files_local ]
    # ----------------------------------------------
    if [[ ~{true='true' false='false' defined(files_local)} == "true" ]]; then
      echo "Processing files from the array" >> $log_file
      
      for file in ~{sep=' ' files_local}; do
        file_name=$(basename "$file")  # Extract just the filename
        echo "Processing $file_name" >> $log_file
        if [[ -f "files/VCFs_inputs/$file_name" ]]; then
          echo "-- File $file_name already exists, skipping" >> $log_file
        
        else
          cp "$file" "files/VCFs_inputs/"
          echo "-- File $file_name copied to files/VCFs_inputs/" >> $log_file
        fi
      done
    fi

    # Create VCFs_list.txt
    ls files/VCFs_inputs/* | sort > $VCFs_list

    # Prepare the folder structure to process in next task
    if [[ $(ls files/VCFs_inputs | wc -l) -gt 0 ]]; then
      file_count=$(ls files/VCFs_inputs/* | wc -l)
      echo "Number of files in VCFs_inputs: $file_count" >> $log_file
      echo "End of Cloud Reader Task" >> $log_file
      tar -czvf files.tar.gz files
    else
      echo "No files to compress, task failed." >> $log_file
      exit 1
    fi

  >>>

  output {
    # Return the compressed file instead of an array of individual files
    File result_cloud_reader = "files.tar.gz"
  }

  runtime {
    # docker: "google/cloud-sdk:slim"
    docker: "ricoandre/cloud-tools:latest"
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task vcf_preprocessor_task {
  input {
    # Data from cloud_reader_task
    File result_cloud_reader

    # Environment Settings
    String docker_version
    Int max_concurrent_processes
    String max_memory

    # Adapted for this Task
    Boolean? single_vcf_mode = true  # Defaul will run VCF files individually

    # Inputs from Pharmcat_vcf_preprocesssor.py
    File? sample_file  # Optional file containing a list of sample IDs
    String? sample_ids  # Optional comma-separated list of sample IDs
    Boolean single_sample = false  # Whether to generate one VCF per sample
    Boolean missing_to_ref = false  # Whether to add missing PGx positions as reference (use with caution)
    Boolean concurrent_mode = false  # Enable concurrent mode
    Boolean no_gvcf_check = false  # Bypass the check for gVCF format
    File? reference_pgx_vcf  # Custom PGx VCF for reference positions
    File? reference_genome  # Custom reference genome (GRCh38)
    Boolean retain_specific_regions = false  # Retain specific regions
    File? reference_regions_to_retain  # BED file specifying PGx regions to retain
    
    # Inputs from Pharmcat_vcf_preprocesssor.py / No works on Could Environment
    # File vcf_file  # Input VCF file (can be a single VCF or a list file with multiple VCFs)
    # String? output_dir = "."  # Output directory for the processed files
    # String? base_filename  # Prefix for the output files
    # Boolean keep_intermediate_files = false  # Whether to keep intermediate files
    # Boolean verbose = false  # Enable verbose output
    # File? bcftools_path  # Optional custom path to bcftools
    # File? bgzip_path  # Optional custom path to bgzip
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
    if [ ! -z "$sample_file" ]; then
      arg+=" -S $sample_file"
    fi
    if [ ! -z "$sample_ids" ]; then
      arg+=" -s $sample_ids"
    fi
    if [ "$single_sample" == "true" ]; then
      arg+=" -ss"
    fi
    if [ "$missing_to_ref" == "true" ]; then
      arg+=" -0"
    fi
    if [ "$concurrent_mode" == "true" ]; then
      arg+=" -c"
    fi
    if [ ! -z "$max_concurrent_processes" ]; then
      arg+=" -cp $max_concurrent_processes"
    fi
    if [ "$no_gvcf_check" == "true" ]; then
      arg+=" -G"
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

    # Process same set of samples across all split VCF files.
    if [ "$single_vcf_mode" == "false" ]; then
      echo "Running VCF-Preprocessor in List File Mode" >> $log_file
      cmd="python3 /pharmcat/pharmcat_vcf_preprocessor.py -vcf files/VCFs_list.txt"
      cmd="$cmd $arg"  # Concatenating the arguments
      echo "Running: $cmd" >> $log_file
      eval $cmd
    # Process each file in the VCFs_list.txt individually
    else
      echo "Running VCF-Preprocessor in VCF File Mode" >> $log_file
      while read -r vcf_file; do
        echo "Processing file: $vcf_file" >> $log_file
        cmd="python3 /pharmcat/pharmcat_vcf_preprocessor.py -vcf $vcf_file"
        cmd="$cmd $arg"  # Concatenating the arguments
        echo "Running: $cmd" >> $log_file
        eval $cmd
      done < files/VCFs_list.txt
    fi

    # Run the command
    echo "Pharmcat_vcf_preprocessor.py finished" >> $log_file

    # Check Results Files
    if [ -n "$(ls files/Results/ 2>/dev/null)" ]; then
      echo "Results files:"
      ls files/Results/* >> $log_file
    else
      echo "No results found in files/Results/" >> $log_file
    fi

    # Package the entire 'files' directory and create a tar.gz file
    # echo "Packaging the 'files' directory..." >> $log_file
    # tar -czvf result_vcf_preprocessor.tar.gz -C files .  # Use -C to change directory and include all contents of 'files' folder
    tar -czvf result_vcf_preprocessor.tar.gz files
  >>>

  output {
      # Return the packaged tar.gz file containing all the processed files
      File result_vcf_preprocessor = "result_vcf_preprocessor.tar.gz"
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}"  # Use the user-specified or default Docker version
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task named_allele_matcher_task {
  input {
    # Data from cloud_reader_task
    File result_vcf_preprocessor

    # Environment Settings
    String docker_version
    Int max_concurrent_processes
    String max_memory
  }

  command <<<
    echo " --------- "
    touch results.txt
  >>>

  output {
      # Return the packaged tar.gz file containing all the processed files
      File result_named_allele_matcher = "results.txt"
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}"  # Use the user-specified or default Docker version
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task phenotyper_task {
  input {
    # Data from cloud_reader_task
    File result_result_named_allele_matcher

    # Environment Settings
    String docker_version
    Int max_concurrent_processes
    String max_memory
  }
  
  command <<<
    echo " --------- "
    touch results.txt
  >>>

  output {
      # Return the packaged tar.gz file containing all the processed files
      File result_phenotyper = "results.txt"
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}"  # Use the user-specified or default Docker version
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task reporter_task {
  input {
    # Data from cloud_reader_task
    File result_phenotyper

    # Environment Settings
    String docker_version
    Int max_concurrent_processes
    String max_memory
  }
  
  command <<<
    echo " --------- "
    touch results.txt
  >>>

  output {
      # Return the packaged tar.gz file containing all the processed files
      File result_reporter = "results.txt"
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}"  # Use the user-specified or default Docker version
    memory: max_memory
    cpu: max_concurrent_processes
  }
}



task cloud_writer_task {
  input {
    File? result_vcf_preprocessor
    String? results_directory
  }

  command <<<
    set -e -x -o pipefail

    # Extract the compressed file from a_cloud_reader_task
    tar -xzvf ~{result_vcf_preprocessor}

    # Start log file
    log_file="files/log.txt"
    echo " " >> $log_file
    echo "-----------------------" >> $log_file
    echo "Start Cloud Writer Task" >> $log_file
    echo "-----------------------" >> $log_file

    # Ensure gsutil is available in this environment
    if ! command -v gsutil &> /dev/null; then
      echo "ERROR: gsutil not found. Please ensure gsutil is available." >> $log_file
      exit 1
    fi

    # Save Results in directory defined by the user
    echo "Copying results to ~{results_directory}" >> $log_file

    # TODO - Add other cloud directories 
    if [[ ~{results_directory} == gs://* ]]; then
      # Copying individual result files
      gsutil cp Results/* "~{results_directory}/" >> $log_file
      # Copying the pre_processor tar.gz as well
      gsutil cp ~{result_vcf_preprocessor} ~{results_directory}/ >> $log_file
    else
      echo "ERROR: Unsupported storage destination. Only gs:// is supported in this task." >> $log_file
      exit 1
    fi

    echo "Cloud Writer Task completed successfully." >> $log_file
  >>>

  output {
    File log = "files/log.txt"
  }

  runtime {
    docker: "ricoandre/cloud-tools:latest"
    memory: "4G"
    cpu: 1
  }
}