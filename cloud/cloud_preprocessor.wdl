version 1.0

workflow pharmcat_vcf_preprocess_workflow {
  input {
    File input_file  # Pode ser um único VCF ou um TSV com URLs
    Boolean is_tsv = false  # Identifica se o arquivo de entrada é um TSV com URLs
    Boolean single_sample_mode = false  # Determina se queremos uma saída para cada sample
  }

  call vcf_preprocess_unified {
    input:
      input_file = input_file,
      is_tsv = is_tsv,
      single_sample = single_sample_mode
  }

  output {
    Array[File] preprocessed_vcf_files = vcf_preprocess_unified.output_vcf_files
  }
}

task vcf_preprocess_unified {
  input {
    File input_file  # Pode ser um único VCF ou um TSV com URLs
    Boolean is_tsv = false  # Identifica se o arquivo de entrada é um TSV com URLs
    Boolean single_sample = false  # Modo para dividir arquivos VCF por sample
  }

  command <<<
    mkdir -p vcf_files

    if [ "~{is_tsv}" == "true" ]; then
      # Baixa arquivos VCF de URLs
      while read -r url; do
        wget -P vcf_files $url
      done < ~{input_file}
      vcf_list=$(ls vcf_files/*)
    else
      # Mover único arquivo VCF para o diretório local
      cp ~{input_file} vcf_files/
      vcf_list="vcf_files/$(basename ~{input_file})"
    fi

    # Rodar o preprocessor
    if [ "~{single_sample}" == "true" ]; then
      python3 pharmcat_vcf_preprocessor.py -vcf $vcf_list -ss
    else
      python3 pharmcat_vcf_preprocessor.py -vcf $vcf_list
    fi
  >>>

  output {
    Array[File] output_vcf_files = glob("*.preprocessed.vcf")
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "8G"
    cpu: 2
  }
}
