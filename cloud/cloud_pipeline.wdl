version 1.0

workflow pharmcat_cloud {
  input {
    Array[String] vcf_urls  # Lista de URLs dos arquivos VCF
  }

  # Task para baixar os arquivos VCF via URLs
  call download_vcf {
    input:
      vcf_urls = vcf_urls
  }

  # Task para rodar o Preprocessor
  call preprocessor_task {
    input:
      vcf_files = download_vcf.local_vcf_files
  }

  # Task para rodar o Named Allele Matcher
  call named_allele_matcher_task {
    input:
      preprocessed_vcf = preprocessor_task.preprocessed_vcf
  }

  # Task para rodar o Phenotyper
  call phenotyper_task {
    input:
      matcher_results = named_allele_matcher_task.matcher_results
  }

  # Task para rodar o Reporter
  call reporter_task {
    input:
      phenotyper_results = phenotyper_task.phenotyper_results
  }

  output {
    File final_report = reporter_task.report
  }
}

# Task para baixar os arquivos VCF
task download_vcf {
  input {
    Array[String] vcf_urls
  }

  command <<<
    mkdir -p vcf_files
    for url in ~{sep = " " vcf_urls}; do
      wget -P vcf_files $url
    done
  >>>

  output {
    Array[File] local_vcf_files = glob("vcf_files/*")
  }

  runtime {
    docker: "appropriate/curl"
    memory: "4G"
    cpu: 1
  }
}

# Task para o Preprocessor
task preprocessor_task {
  input {
    Array[File] vcf_files
  }

  command <<<
    pharmcat_preprocessor.py -vcf ~{sep = " " vcf_files}
  >>>

  output {
    Array[File] preprocessed_vcf = glob("*.preprocessed.vcf")
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "8G"
    cpu: 2
  }
}

# Task para o Named Allele Matcher
task named_allele_matcher_task {
  input {
    Array[File] preprocessed_vcf
  }

  command <<<
    pharmcat_named_allele_matcher.py -vcf ~{sep = " " preprocessed_vcf}
  >>>

  output {
    Array[File] matcher_results = glob("*.matcher.results")
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "8G"
    cpu: 2
  }
}

# Task para o Phenotyper
task phenotyper_task {
  input {
    Array[File] matcher_results
  }

  command <<<
    pharmcat_phenotyper.py -results ~{sep = " " matcher_results}
  >>>

  output {
    Array[File] phenotyper_results = glob("*.phenotyper.results")
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "8G"
    cpu: 2
  }
}

# Task para o Reporter
task reporter_task {
  input {
    Array[File] phenotyper_results
  }

  command <<<
    pharmcat_reporter.py -results ~{sep = " " phenotyper_results}
  >>>

  output {
    File report = glob("*.final.report")[0]
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "8G"
    cpu: 2
  }
}
