version 1.0

workflow PharmCAT_VCF_Preprocessor {
  input {
    File? urls_file  # Optional input file containing list of URLs
    Array[File]? local_files  # Optional array of files
    String? directory_path  # Read all VCF from a diretory
    String? directory_results  # Write the Results in Cloud Diretory
    String pharmcat_version = "2.13.0"
    Int max_concurrent_processes = 1
    String max_memory = "4G"
  }

  call a_cloud_reader_task {
    input:
      urls_file = urls_file,
      local_files = local_files,
      directory_path = directory_path,
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory
  }

  call b_vcf_preprocessor {
    input:
      compressed_files = a_cloud_reader_task.compressed_files,
      docker_version = pharmcat_version,
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory,
  }

  call c_cloud_writer_task {
    input:
      pre_processor = b_vcf_preprocessor.pre_processor,
      directory_results = directory_results
  }

  output {
    # Array[File] pre_processor = b_vcf_preprocessor.pre_processor
    File pre_processor = b_vcf_preprocessor.pre_processor
    File log = c_cloud_writer_task.log
  }
}

task a_cloud_reader_task {
  input {
    File? urls_file  # Optional input file containing list of URLs
    Array[File]? local_files  # Array of input files
    String? directory_path # Directory name to read all files inside
    Int max_concurrent_processes
    String max_memory
  }

  command <<<
    set -e -x -o pipefail

    # Install necessary tools
    apt-get update && apt-get install -y \
      wget \
      curl \
      python3 \
      python3-pip \
      unzip

    # Create folders
    mkdir -p files
    mkdir -p files/VCFs_inputs

    # Create log file
    log_file="files/log.txt"
    touch $log_file
    echo "Start Cloud Reader Task" >> $log_file

    # Create the txt file
    VCFs_list="files/VCFs_list.txt"
    touch $VCFs_list

    # Check gsutil
    gsutil --version >> $log_file

    # Process the directory input
    if [[ ~{true='true' false='false' defined(directory_path)} == "true" ]]; then
      echo "Processing directory: ~{directory_path}" >> $log_file
      # Ensure we're working with a gs:// URL
      if [[ ~{directory_path} == gs://* ]]; then
        echo "Copying all VCF files from directory: ~{directory_path}" >> $log_file
        # List all the VCF files in the directory
        gsutil ls "~{directory_path}/*.vcf.*" >> $log_file
        # Copy all the VCF files from the directory to the local folder
        gsutil cp "~{directory_path}/*.vcf.*" files/VCFs_inputs/ >> $log_file
        # Add all copied files to the VCFs list file
        ls files/VCFs_inputs/*.vcf.* >> files/VCFs_list.txt
        echo "All VCF files from ~{directory_path} have been copied to files/VCFs_inputs/" >> $log_file
      # TODO: Add support for other cloud directories as we extend
      else
        echo "ERROR: The directory path is not a valid gs:// URL. Skipping file copy." >> $log_file
      fi
    fi

    # Process urls from file
    if [[ -n "~{urls_file}" ]]; then
      echo "Start to Read URLs from File" >> $log_file
      # cat ~{urls_file} >> $log_file
      # bug - while no works in this logic
      for url in $(cat ~{urls_file}); do
        if [[ $url == http* ]]; then
          echo "-- Get $url by wget" >> $log_file
          wget -P files/VCFs_inputs $url --verbose
        elif [[ $url == gs://* ]]; then
          echo "-- Get $url by gsutil" >> $log_file
          gsutil cp $url files/VCFs_inputs/
        else
          echo "-- URL formant not support: $url" >> $log_file
        fi
      done
    fi

    # Check if local_files is defined and process it
    if [[ ~{true='true' false='false' defined(local_files)} == "true" ]]; then
      echo "Processing files from the array" >> $log_file
      for file in ~{sep=' ' local_files}; do
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

    # TODO: Keep the list in apha order
    # Create VCFs_list.txt
    ls files/VCFs_inputs/* > $VCFs_list

    # Prepare the folder structure to process in next task
    if [[ $(ls files/VCFs_inputs | wc -l) -gt 0 ]]; then
      echo "Compressing the downloaded files..."  >> $log_file
      echo "Finish the Cloud Reader Task" >> $log_file
      echo " " >> $log_file
      tar -czvf files.tar.gz files
    else
      echo "No files to compress, task failed." >> $log_file
      exit 1
    fi

  >>>

  output {
    # Return the compressed file instead of an array of individual files
    File compressed_files = "files.tar.gz"
  }

  runtime {
    docker: "google/cloud-sdk:slim"
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task b_vcf_preprocessor {
  input {
    # Data from a_cloud_reader_task
    File compressed_files

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
    tar -xzvf ~{compressed_files}

    # Start log file
    log_file="files/log.txt"
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
    eval $cmd
    echo "Pharmcat_vcf_preprocessor.py finished" >> $log_file

    # Check Results Files
    if [ -n "$(ls files/Results/ 2>/dev/null)" ]; then
      ls files/Results/* >> $log_file
    else
      echo "No results found in files/Results/" >> $log_file
    fi

    # Package the entire 'files' directory and create a tar.gz file
    echo "Packaging the 'files' directory..." >> $log_file
    tar -czvf pre_processor.tar.gz -C files .  # Use -C to change directory and include all contents of 'files' folder
  >>>

output {
    # Return the packaged tar.gz file containing all the processed files
    File pre_processor = "pre_processor.tar.gz"
}

  runtime {
    docker: "pgkb/pharmcat:${docker_version}"  # Use the user-specified or default Docker version
    memory: max_memory
    cpu: max_concurrent_processes
  }
}

task c_cloud_writer_task {
  input {
    File pre_processor
    String? directory_results
  }

  command <<<
    set -e -x -o pipefail

    # Extract the compressed file from a_cloud_reader_task
    tar -xzvf ~{pre_processor}

    # Start log file
    log_file="log.txt"
    touch $log_file
    echo "-----------------------" >> $log_file
    echo "Start Cloud Writer Task" >> $log_file
    echo "-----------------------" >> $log_file

    # Ensure gsutil is available in this environment
    if ! command -v gsutil &> /dev/null; then
      echo "ERROR: gsutil not found. Please ensure gsutil is available." >> $log_file
      exit 1
    fi

    # Save Results in directory defined by the user
    echo "Copying results to ~{directory_results}" >> $log_file

    if [[ ~{directory_results} == gs://* ]]; then
      # Copying individual result files
      gsutil cp Results/* "~{directory_results}/" >> $log_file
      # Copying the pre_processor tar.gz as well
      gsutil cp ~{pre_processor} ~{directory_results}/ >> $log_file
    else
      echo "ERROR: Unsupported storage destination. Only gs:// is supported in this task." >> $log_file
      exit 1
    fi

    echo "Cloud Writer Task completed successfully." >> $log_file
  >>>

  output {
    File log = "log.txt"
  }

  runtime {
    docker: "google/cloud-sdk:slim"  # Use a Docker image that includes gsutil
    memory: "4G"
    cpu: 1
  }
}
