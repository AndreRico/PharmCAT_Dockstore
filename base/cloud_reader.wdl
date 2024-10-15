version 1.0

workflow download_workflow {
  input {
    File urls  # Input file containing list of URLs (one per line)
  }

  call download_task {
    input:
      urls_file = urls  # Pass the file containing the list of URLs to the task
  }

  output {
    Array[File] downloaded_files = download_task.downloaded_files
  }
}

task download_task {
  input {
    File urls_file  # The input file containing list of URLs
  }

  command <<<
    set -e -x -o pipefail

    apt-get update && apt-get install -y \
      wget \
      curl \
      python3 \
      python3-pip \
      unzip

    # # Baixar e instalar o Google Cloud SDK diretamente via tarball
    # wget https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-367.0.0-linux-x86_64.tar.gz
    # tar -xzf google-cloud-sdk-367.0.0-linux-x86_64.tar.gz
    # ./google-cloud-sdk/install.sh -q

    # # Adicionar gsutil ao PATH
    # export PATH=$PATH:/google-cloud-sdk/bin

    # Exibir o conteúdo do arquivo para fins de debug
    echo "Conteúdo do arquivo URLs:"
    echo >> file.txt
    cat ~{urls_file}

    # Criar um diretório para armazenar os arquivos baixados
    mkdir -p downloaded_files

    touch downloaded_files/file__TESTE__SAIDA.txt
    echo "add one row" >> downloaded_files/file__TESTE__SAIDA.txt

    # testar se o gsutil está instalado
    gsutil --version >> downloaded_files/file__TESTE__SAIDA.txt


    # Ler as URLs do arquivo de input e baixar cada uma
    while read -r url; do
      if [[ $url == http* ]]; then
        echo "entrou no if para o $url" >> downloaded_files/file__TESTE__SAIDA.txt
        echo "Baixando $url via wget"
        wget -P downloaded_files $url --verbose
        
      elif [[ $url == gs://* ]]; then
        echo "entrou no if para o $url" >> downloaded_files/file__TESTE__SAIDA.txt
        echo "Baixando $url via gsutil"
        gsutil cp $url downloaded_files/
      else
        echo "Formato de URL não suportado: $url"
      fi
    done < ~{urls_file}
  >>>

  output {
    # Capture all the downloaded files from the 'downloaded_files' directory
    Array[File] downloaded_files = glob("downloaded_files/*")
  }

  runtime {
    docker: "google/cloud-sdk:slim"  # Ensure the Docker image has both wget and gsutil
    memory: "4G"
    cpu: 2
  }
}
