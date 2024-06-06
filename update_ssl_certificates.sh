#!/bin/bash

# Configurações
CERT_NAME="my-cert-$(date +%Y%m%d%H%M%S)" # Nome único para o certificado baseado na data e hora
CERT_DIR="/mnt/certificados" # Diretório onde os novos certificados são armazenados
OLD_CERT_FILE="/path/to/old/certificate.crt" # Caminho para o certificado antigo
OLD_KEY_FILE="/path/to/old/private.key" # Caminho para a chave privada antiga
PROJECT_ID="infra-bi-355620" # ID do seu projeto no Google Cloud
FORWARDING_RULE_NAME="lb-cloud-run-forwarding-rule" # Nome da regra de encaminhamento do Load Balancer
TARGET_HTTPS_PROXY_NAME="lb-cloud-run-target-proxy" # Nome do proxy HTTPS de destino
REGION="us-east4" # Região do Load Balancer

# Montar o diretório de rede (se necessário)
sudo mount -t cifs //fs/web/certificados/2024 $CERT_DIR -o username=usuário,password=senha

# Verificar novos certificados
# Procurar por novos arquivos .crt no diretório que são mais novos que o arquivo antigo
NEW_CERT_FILE=$(find $CERT_DIR -name "*.crt" -newer $OLD_CERT_FILE)
# Procurar por novos arquivos .key no diretório que são mais novos que o arquivo antigo
NEW_KEY_FILE=$(find $CERT_DIR -name "*.key" -newer $OLD_KEY_FILE)

# Verificar se novos arquivos de certificado e chave foram encontrados
if [[ -n $NEW_CERT_FILE && -n $NEW_KEY_FILE ]]; then
    echo "Novos certificados encontrados. Criando novo certificado no Certificate Manager..."

    # Criar um novo certificado no Certificate Manager
    gcloud beta compute ssl-certificates create $CERT_NAME \
      --project=$PROJECT_ID \
      --global \
      --certificate=$NEW_CERT_FILE \
      --private-key=$NEW_KEY_FILE

    # Verificar se o comando de criação foi bem-sucedido
    if [ $? -eq 0 ]; then
        echo "Novo certificado $CERT_NAME criado com sucesso."

        # Atualizar os arquivos de referência para os novos certificados
        cp $NEW_CERT_FILE $OLD_CERT_FILE
        cp $NEW_KEY_FILE $OLD_KEY_FILE

        # Atualizar o Load Balancer para usar o novo certificado
        echo "Atualizando o Load Balancer para usar o novo certificado..."

        # Verificar se o proxy HTTPS de destino existe
        PROXY_EXISTS=$(gcloud compute target-https-proxies describe $TARGET_HTTPS_PROXY_NAME --project=$PROJECT_ID --format="value(name)")

        if [[ -n $PROXY_EXISTS ]]; then
            # Atualizar o proxy HTTPS de destino para referenciar o novo certificado
            gcloud compute target-https-proxies update $TARGET_HTTPS_PROXY_NAME \
              --project=$PROJECT_ID \
              --ssl-certificates=$CERT_NAME

            if [ $? -eq 0 ]; then
                echo "Load Balancer atualizado com sucesso para usar o novo certificado."
            else
                echo "Erro ao atualizar o Load Balancer."
            fi
        else
            echo "Proxy HTTPS de destino não encontrado."
        fi
    else
        echo "Erro ao criar o novo certificado."
    fi
else
    echo "Nenhum novo certificado encontrado."
fi

# Desmontar o diretório de rede (se necessário)
sudo umount $CERT_DIR
