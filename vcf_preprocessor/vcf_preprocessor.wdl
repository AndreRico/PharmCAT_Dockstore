version 1.0

workflow PharmCAT_VCF_Preprocessor {
  input {
    File? urls_file  # Optional input file containing list of URLs
    Array[File]? local_files  # Optional array of files
    File simple_file  # Single file input
    Boolean copy_entire_folder = false  # Flag to indicate if all files in the folder should be copied
    String pharmcat_version = "2.13.0"
    Int max_concurrent_processes = 1
    String max_memory = "4G"
  }

  call a_cloud_reader_task {
    input:
      urls_file = urls_file,
      local_files = local_files,
      simple_file = simple_file,
      copy_entire_folder = copy_entire_folder,
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

  output {
    Array[File] pre_processor = b_vcf_preprocessor.pre_processor
  }
}

task a_cloud_reader_task {
  input {
    File? urls_file  # Optional input file containing list of URLs
    Array[File]? local_files  # Array of input files
    File simple_file  # Single file input
    Boolean copy_entire_folder  # Flag to copy all files from the folder
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

    # Process the single file input
    if [[ ~{true='true' false='false' defined(simple_file)} == "true" ]]; then
      echo "Processing single file: ~{simple_file}" >> $log_file
      gsutil cp ~{simple_file} files/VCFs_inputs/
      echo "~{simple_file}" >> files/VCFs_list.txt
    
      # If the flag is set to copy the entire folder, process all files in the folder
      if [[ ~{copy_entire_folder} == "true" ]]; then
        # Ensure we're working with a gs:// URL
        folder_path=$(dirname ~{simple_file})
        
        echo("$folder_path") # DEBUG

        # Convert the local file path to a Cloud Storage gs:// URL
        if [[ $folder_path == gs://* ]]; then
          echo "Copying all VCF files from folder: $folder_path" >> $log_file
          gsutil ls "$folder_path/*.vcf.*" >> $log_file
          gsutil cp "$folder_path/*.vcf.*" files/VCFs_inputs/ >> $log_file

          # Add all copied files to the list
          ls files/VCFs_inputs/*.vcf.* >> files/VCFs_list.txt
        else
          echo "ERROR: The file path is not a valid gs:// URL. Skipping folder copy." >> $log_file
        fi
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
    File compressed_files

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

    String docker_version
    Int max_concurrent_processes
    String max_memory

    # -- Fields to check if works on cloud environment --
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
  
    # Extract the compressed file
    tar -xzvf ~{compressed_files}

    # Construct the command for the preprocessor
    cmd="python3 /pharmcat/pharmcat_vcf_preprocessor.py"
    cmd+=" -vcf files/VCFs_list.txt" # only if the same 
    # Process file by VCF file instead the txt! (but we need keep the txt if the use flag to process as txt)
    cmd+=" -o files/Results"

    if [ ! -z "$sample_file" ]; then
      cmd+=" -S $sample_file"
    fi

    if [ ! -z "$sample_ids" ]; then
      cmd+=" -s $sample_ids"
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

    if [ "$no_gvcf_check" == "true" ]; then
      cmd+=" -G"
    fi

    # Run the command
    eval $cmd
  >>>

  output {
    # Return the extracted files
    Array[File] pre_processor = glob("files/VCFs_inputs/*")
  }

  runtime {
    docker: "pgkb/pharmcat:${docker_version}"  # Use the user-specified or default Docker version
    memory: max_memory
    cpu: max_concurrent_processes
  }
}
