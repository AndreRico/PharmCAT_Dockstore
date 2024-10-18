version 1.0

workflow pharmcat_pipeline {
  input {
    File? files_list  # Optional input file containing list of URLs
    Array[File]? files_local  # Optional array of files
    String? files_directory  # Read all VCF from a diretory
    String? results_directory  # Write the Results in Cloud Diretory
    Int max_concurrent_processes = 1
    String max_memory = "4G"
  }

  call a_cloud_reader_task {
    input:
      files_list = files_list,
      max_concurrent_processes = max_concurrent_processes,
      max_memory = max_memory
  }

  output {
    File compressed_files = a_cloud_reader_task.compressed_files
  }
}

task a_cloud_reader_task {
  input {
    File? files_list  # Optional input file containing list of URLs
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

  >>>

  output {
    # Return the compressed file instead of an array of individual files
    File compressed_files = "files/log.txt"
  }

  runtime {
    docker: "google/cloud-sdk:slim"
    memory: max_memory
    cpu: max_concurrent_processes
  }
}