# Use uma imagem base leve, como Alpine ou Ubuntu
FROM ubuntu:20.04

# Instalar ferramentas básicas: wget, curl, awscli, gsutil, azcopy
RUN apt-get update && \
    apt-get install -y \
    wget \
    curl \
    unzip \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Instalar AWS CLI
RUN pip3 install awscli

# Instalar Google Cloud SDK (inclui gsutil)
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get install -y apt-transport-https ca-certificates && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && apt-get install -y google-cloud-sdk

# Instalar o AzCopy para acesso ao Azure
RUN wget https://aka.ms/downloadazcopy-v10-linux -O azcopy.tar.gz && \
    tar -xvf azcopy.tar.gz --strip-components=1 && \
    mv ./azcopy /usr/bin/ && \
    rm azcopy.tar.gz

# Definir entrypoint padrão como bash para facilitar o uso
ENTRYPOINT ["/bin/bash"]
