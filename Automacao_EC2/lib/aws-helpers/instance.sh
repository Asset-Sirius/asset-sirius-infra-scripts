#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE INSTÂNCIAS EC2
# ============================================================================

# Função para criar instância EC2
criar_instancia() {
    local nome_infra="$1"
    local image_id="$2"
    local instance_type="$3"
    local key_name="$4"
    local subnet_id="$5"
    local device_name="$6" 
    local count="$7"
    local security_group_ids="$8"
    local volume_size="$9"
    local volume_type="${10}"
    
    echo "Criando instância EC2 '$nome_infra'..." >&2
    pausar 1
    
    local instance_id=$(aws ec2 run-instances \
        --image-id "$image_id" \
        --instance-type "$instance_type" \
        --key-name "$key_name" \
        --subnet-id "$subnet_id" \
        --block-device-mappings "[{\"DeviceName\":\"$device_name\",\"Ebs\":{\"VolumeSize\":$volume_size,\"VolumeType\":\"$volume_type\"}}]" \
        --count "$count" \
        --security-group-ids "$security_group_ids" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$nome_infra}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [ $? -eq 0 ]; then
        echo "" >&2
        echo "[OK] Instância criada com sucesso!" >&2
        echo "  Instance ID: $instance_id" >&2
        echo "" >&2
        pausar 1
        
        echo "$instance_id"  # Retorna apenas o Instance ID
        return 0
    else
        echo "[ERRO] Erro ao criar a instância" >&2
        echo "" >&2
        return 1
    fi
}

# Função para obter IP público de uma instância
obter_ip_publico_instancia() {
    local instance_id="$1"
    local max_tentativas=10
    local tentativa=0
    
    echo "Aguardando IP público ser atribuído..." >&2
    
    while [ $tentativa -lt $max_tentativas ]; do
        local ip_publico=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text 2>/dev/null)
        
        if [ "$ip_publico" != "None" ] && [ -n "$ip_publico" ] && [ "$ip_publico" != "null" ]; then
            echo "$ip_publico"
            return 0
        fi
        
        ((tentativa++))
        sleep 2
    done
    
    echo "" >&2
    return 1
}
