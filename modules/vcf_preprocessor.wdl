version 1.0

workflow vcf_preprocessor_workflow {
  meta {
    author: "ClinPGx"
    email: "pharmcat@pharmgkb.org"
    description: "This workflow runs the PharmCAT VCF Preprocessor to prepare a VCF file for further analysis."
  }

  input {
    File vcf_file  # Input VCF file (can be a single VCF or a list file with multiple VCFs)
    File? sample_file  # Optional file containing a list of sample IDs
    String? sample_ids  # Optional comma-separated list of sample IDs
    String? output_dir = "."  # Output directory for the processed files
    String? base_filename  # Prefix for the output files
    Boolean keep_intermediate_files = false  # Whether to keep intermediate files
    Boolean single_sample = false  # Whether to generate one VCF per sample
    Boolean missing_to_ref = false  # Whether to add missing PGx positions as reference (use with caution)
    Boolean concurrent_mode = false  # Enable concurrent mode
    Int? max_concurrent_processes  # Maximum number of concurrent processes
    Boolean verbose = false  # Enable verbose output
    Boolean no_gvcf_check = false  # Bypass the check for gVCF format
    File? reference_pgx_vcf  # Custom PGx VCF for reference positions
    File? reference_genome  # Custom reference genome (GRCh38)
    Boolean retain_specific_regions = false  # Retain specific regions
    File? reference_regions_to_retain  # BED file specifying PGx regions to retain
    ## File? bcftools_path  # Optional custom path to bcftools
    ## File? bgzip_path  # Optional custom path to bgzip
  }

  call vcf_preprocessor_task {
    input:
      vcf_file = vcf_file,
      sample_file = sample_file,
      sample_ids = sample_ids,
      output_dir = output_dir,
      base_filename = base_filename,
      keep_intermediate_files = keep_intermediate_files,
      single_sample = single_sample,
      missing_to_ref = missing_to_ref,
      concurrent_mode = concurrent_mode,
      max_concurrent_processes = max_concurrent_processes,
      verbose = verbose,
      no_gvcf_check = no_gvcf_check,
      reference_pgx_vcf = reference_pgx_vcf,
      reference_genome = reference_genome,
      retain_specific_regions = retain_specific_regions,
      reference_regions_to_retain = reference_regions_to_retain,
      ## bcftools_path = bcftools_path,
      ## bgzip_path = bgzip_path
  }

  output {
    Array[File] preprocessed_vcf_files = vcf_preprocessor_task.output_vcf_files
  }
}

task vcf_preprocessor_task {
  meta {
    author: "ClinPGx"
    email: "pharmcat@pharmgkb.org"
    description: "This task runs the PharmCAT VCF Preprocessor script to prepare a VCF file for PharmCAT."
  }

  input {
    File vcf_file  # The original VCF file to preprocess
    File? sample_file  # Optional file with sample IDs
    String? sample_ids  # Comma-separated list of sample IDs
    String? output_dir = "."  # Directory for output
    String? base_filename  # Output file prefix
    Boolean keep_intermediate_files = false  # Keep intermediate files
    Boolean single_sample = false  # Generate one VCF per sample
    Boolean missing_to_ref = false  # Add missing PGx positions as reference
    Boolean concurrent_mode = false  # Enable concurrent mode
    Int? max_concurrent_processes  # Max concurrent processes in concurrent mode
    Boolean verbose = false  # Verbose output
    Boolean no_gvcf_check = false  # Bypass gVCF check
    File? reference_pgx_vcf  # Custom PGx reference VCF file
    File? reference_genome  # Custom reference genome (FASTA)
    Boolean retain_specific_regions = false  # Retain specific regions
    File? reference_regions_to_retain  # BED file specifying regions to retain
    ## File? bcftools_path  # Custom path to bcftools
    ## File? bgzip_path  # Custom path to bgzip
  }

  command <<<
    set -e -x -o pipefail

    # Create output directory if it doesn't exist
    mkdir -p ~{output_dir}

    # Construct the command
    cmd="python3 pharmcat_vcf_preprocessor.py -vcf ~{vcf_file}"

    # Optional arguments
    ~{if defined(sample_file) then 'cmd+=" -S " + sample_file'}
    ~{if defined(sample_ids) then 'cmd+=" -s " + sample_ids'}
    ~{if defined(output_dir) then 'cmd+=" -o " + output_dir'}
    ~{if defined(base_filename) then 'cmd+=" -bf " + base_filename'}
    ~{if keep_intermediate_files then 'cmd+=" -k "'}
    ~{if single_sample then 'cmd+=" -ss "'}
    ~{if missing_to_ref then 'cmd+=" -0 "'}
    ~{if concurrent_mode then 'cmd+=" -c "'}
    ~{if defined(max_concurrent_processes) then 'cmd+=" -cp " + max_concurrent_processes'}
    ~{if verbose then 'cmd+=" -v "'}
    ~{if no_gvcf_check then 'cmd+=" -G "'}
    ~{if defined(reference_pgx_vcf) then 'cmd+=" -refVcf " + reference_pgx_vcf'}
    ~{if defined(reference_genome) then 'cmd+=" -refFna " + reference_genome'}
    ~{if retain_specific_regions then 'cmd+=" -R "'}
    ~{if defined(reference_regions_to_retain) then 'cmd+=" -refRegion " + reference_regions_to_retain'}
    # NOTE: The input parameters bcftools_path and bgzip_path are not applicable when executing
    #   the workflow in a cloud environment using the PharmCAT Docker image. These tools are 
    #   already included in the Docker image and available in the system's PATH. Therefore, no 
    #   additional configuration for these paths is required.
    ## ~{if defined(bcftools_path) then 'cmd+=" -bcftools " + bcftools_path'}
    ## ~{if defined(bgzip_path) then 'cmd+=" -bgzip " + bgzip_path'}

    # Run the command
    echo $cmd
    eval $cmd
  >>>

  output {
    Array[File] output_vcf_files = glob("~{output_dir}/*.vcf*")
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "16G"
    cpu: 4
  }
}
