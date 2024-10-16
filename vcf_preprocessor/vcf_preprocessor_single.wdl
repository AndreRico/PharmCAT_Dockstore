version 1.0

workflow PharmCAT_VCF_Preprocessor {
  input {
    File urls  # Input file containing list of URLs (one per line)
    String docker_version = "2.13.0"
    Int max_concurrent_processes = 1
    String max_memory = "4G"
  }

  call a_download_task {
    input:
      urls_file = urls,  # Pass the file containing the list of URLs to the task
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory
  }

  call b_vcf_preprocessor {
    input:
      compressed_files = a_download_task.compressed_files,
      docker_version = docker_version,
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory,
  }

  output {
    Array[File] pre_processor = b_vcf_preprocessor.pre_processor
  }
}

task a_download_task {
  input {
    Int max_concurrent_processes
    String max_memory
    File urls_file
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

    # Set Folders
    mkdir -p files
    mkdir -p files/VCFs_inputs

    # Create a log file
    log_file="files/log_cloud_reader.txt"
    touch $log_file
    echo "Start Cloud Reader Task" >> $log_file

    # Create a list path file
    VCFs_list="files/VCFs_list.txt"
    touch $VCFs_list

    # Check if the gsutil is installed
    gsutil --version >> $log_file

    # Add file list in the log
    echo "Files list:" >> $log_file
    cat ~{urls_file} >> $log_file

    # Read the URLs from the input file and download each one
    while read -r url; do
      if [[ $url == http* ]]; then
        echo "Starting $url" >> $log_file
        wget -P files/VCFs_inputs $url --verbose

      elif [[ $url == gs://* ]]; then
        echo "Starting $url" >> $log_file
        gsutil cp $url files/VCFs_inputs/

      else
        echo "ERROR in $url" >> $log_file
      fi
    done < ~{urls_file}

    # list all files in the folder and save in the VCFs_list.txt
    ls files/VCFs_inputs/* > $VCFs_list

    # Compress the files directory into a tar.gz file
    tar -czvf files.tar.gz files
  >>>

  output {
    # Return the compressed file instead of an array of individual files
    File compressed_files = "files.tar.gz"
  }

  runtime {
    docker: "google/cloud-sdk:slim"  # Ensure the Docker image has both wget and gsutil
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
    cmd+=" -vcf files/VCFs_list.txt"
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