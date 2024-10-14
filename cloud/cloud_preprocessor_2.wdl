version 1.0

workflow pharmcat_vcf_preprocess_workflow {
  input {
    File input_file  # Pode ser um único VCF ou um arquivo TSV com URLs
    Boolean is_tsv = false  # Identifica se o arquivo de entrada é um TSV com URLs
    Boolean single_sample_mode = false  # Determina se queremos uma saída para cada sample
  }

  Array[File] vcf_files  # Array de arquivos VCF que será passado para a task de preprocessor

  # Task para verificar e processar o tipo de entrada
  if (is_tsv) {
    call download_and_create_tsv {
      input:
        tsv_file = input_file
    }
    # Atribui os arquivos baixados ao array vcf_files
    vcf_files = download_and_create_tsv.local_vcf_files
  } else {
    call move_vcf_to_local {
      input:
        vcf_file = input_file
    }
    # Atribui o arquivo VCF movido ao array vcf_files
    vcf_files = [move_vcf_to_local.local_vcf]
  }

  # Chama o preprocessor com os arquivos VCF baixados ou movidos
  call vcf_preprocessor {
    input:
      vcf_files = vcf_files,
      single_sample = single_sample_mode
  }

  output {
    Array[File] preprocessed_vcf_files = vcf_preprocessor.output_vcf_files
  }
}

# Task para baixar arquivos VCF de URLs e criar um novo TSV com paths locais
task download_and_create_tsv {
  input {
    File tsv_file
  }

  command <<<
    mkdir -p vcf_files
    while read -r url; do
      wget -P vcf_files $url
    done < ~{tsv_file}
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

# Task para mover um único VCF para o container e criar um TSV local
task move_vcf_to_local {
  input {
    File vcf_file
  }

  command <<<
    mkdir -p vcf_files
    cp ~{vcf_file} vcf_files/
  >>>

  output {
    File local_vcf = "vcf_files/$(basename ~{vcf_file})"
  }

  runtime {
    docker: "pgkb/pharmcat:2.13.0"
    memory: "4G"
    cpu: 1
  }
}

# Task para rodar o VCF Preprocessor com os arquivos baixados/movidos
task vcf_preprocessor {
  input {
    Array[File] vcf_files
    Boolean single_sample  # Modo para dividir arquivos VCF por sample
  }

  command <<<
    if [ "~{single_sample}" == "true" ]; then
      python3 pharmcat_vcf_preprocessor.py -vcf ~{sep = " " vcf_files} -ss
    else
      python3 pharmcat_vcf_preprocessor.py -vcf ~{sep = " " vcf_files}
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
