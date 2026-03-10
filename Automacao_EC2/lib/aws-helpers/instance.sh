#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE INSTÂNCIAS EC2
# ============================================================================

# Função para criar instância EC2 para infraestrutura (com opções de IP privado e público)
criar_instancia_infra() {
    local nome="$1"
    local image_id="$2"
    local instance_type="$3"
    local key_name="$4"
    local subnet_id="$5"
    local sg_id="$6"
    local private_ip="$7"
    local associar_ip_publico="$8"

    msg_info "Criando instância EC2 '$nome'..."
    pausar 1

    local cmd="aws ec2 run-instances"
    cmd="$cmd --image-id $image_id"
    cmd="$cmd --instance-type $instance_type"
    cmd="$cmd --key-name $key_name"
    cmd="$cmd --subnet-id $subnet_id"
    cmd="$cmd --security-group-ids $sg_id"
    cmd="$cmd --count 1"
    cmd="$cmd --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value=$nome}]\""

    if [ -n "$private_ip" ]; then
        cmd="$cmd --private-ip-address $private_ip"
    fi

    if [ "$associar_ip_publico" == "true" ]; then
        cmd="$cmd --associate-public-ip-address"
    else
        cmd="$cmd --no-associate-public-ip-address"
    fi

    cmd="$cmd --query Instances[0].InstanceId --output text"

    local instance_id=$(eval $cmd)

    if [ $? -eq 0 ] && [ -n "$instance_id" ]; then
        msg_sucesso "Instância '$nome' criada: $instance_id"
        echo "" >&2
        echo "$instance_id"
        return 0
    else
        msg_erro "Falha ao criar instância '$nome'"
        return 1
    fi
}

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

# Função para listar instâncias EC2
listar_instancias_ec2() {
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                         INSTÂNCIAS EC2 DISPONÍVEIS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    # Obter lista de instâncias
    local instancias=$(aws ec2 describe-instances \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null)
    
    if [ -z "$instancias" ]; then
        msg_aviso "Nenhuma instância EC2 encontrada na região configurada."
        echo "" >&2
        echo "═══════════════════════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        return 1
    fi
    
    # Exibir em formato de tabela
    echo "$instancias" | awk 'BEGIN {
        printf "%-4s %-25s %-20s %-15s %-30s\n", "Nº", "INSTANCE ID", "STATUS", "TIPO", "NOME" | "cat >&2"
        printf "%-4s %-25s %-20s %-15s %-30s\n", "----", "-------------------------", "--------------------", "---------------", "------------------------------" | "cat >&2"
    }
    {
        nome = ($4 != "" && $4 != "None") ? $4 : "Sem nome"
        printf "%-4d %-25s %-20s %-15s %-30s\n", NR, $1, $2, $3, nome | "cat >&2"
    }'
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    return 0
}

# Função para obter Instance ID por índice
obter_instance_id_por_indice() {
    local indice="$1"
    
    local instance_id=$(aws ec2 describe-instances \
        --query 'Reservations[*].Instances[*].[InstanceId]' \
        --output text | sed -n "${indice}p")
    
    echo "$instance_id"
}

# Função para obter informações detalhadas da instância
obter_info_instancia() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress,KeyName,SecurityGroups[0].GroupId,SubnetId,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null
}

# Função para exibir detalhes da instância
exibir_detalhes_instancia() {
    local instance_id="$1"
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                         DETALHES DA INSTÂNCIA" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    local info=$(obter_info_instancia "$instance_id")
    
    if [ -z "$info" ]; then
        msg_erro "Não foi possível obter informações da instância."
        return 1
    fi
    
    local instance_id=$(echo "$info" | awk '{print $1}')
    local status=$(echo "$info" | awk '{print $2}')
    local tipo=$(echo "$info" | awk '{print $3}')
    local ip_publico=$(echo "$info" | awk '{print $4}')
    local ip_privado=$(echo "$info" | awk '{print $5}')
    local key_name=$(echo "$info" | awk '{print $6}')
    local sg_id=$(echo "$info" | awk '{print $7}')
    local subnet_id=$(echo "$info" | awk '{print $8}')
    local nome=$(echo "$info" | awk '{print $9}')
    
    [ "$nome" == "None" ] && nome="Sem nome"
    [ "$ip_publico" == "None" ] && ip_publico="N/A"
    [ "$ip_privado" == "None" ] && ip_privado="N/A"
    [ "$key_name" == "None" ] && key_name="N/A"
    [ "$sg_id" == "None" ] && sg_id="N/A"
    
    echo "  Instance ID:        $instance_id" >&2
    echo "  Nome:               $nome" >&2
    echo "  Status:             $status" >&2
    echo "  Tipo:               $tipo" >&2
    echo "  IP Público:         $ip_publico" >&2
    echo "  IP Privado:         $ip_privado" >&2
    echo "  Key Pair:           $key_name" >&2
    echo "  Security Group:     $sg_id" >&2
    echo "  Subnet ID:          $subnet_id" >&2
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
}

# Função para encerrar instância EC2
encerrar_instancia() {
    local instance_id="$1"
    
    msg_info "Encerrando instância $instance_id..."
    echo "" >&2
    pausar 2
    
    # Executar comando de término
    aws ec2 terminate-instances --instance-ids "$instance_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        msg_sucesso "Instância $instance_id foi marcada para encerramento!"
        echo "" >&2
        msg_info "A instância será encerrada em alguns instantes."
        msg_info "Volumes EBS associados serão excluídos automaticamente (se configurados)."
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao encerrar a instância $instance_id"
        echo "" >&2
        return 1
    fi
}

# Função para parar instância (sem encerrar)
parar_instancia() {
    local instance_id="$1"
    
    msg_info "Parando instância $instance_id..."
    echo "" >&2
    pausar 2
    
    aws ec2 stop-instances --instance-ids "$instance_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        msg_sucesso "Instância $instance_id foi parada com sucesso!"
        echo "" >&2
        msg_info "A instância pode ser reiniciada posteriormente."
        msg_info "Você não será cobrado por uso de instância enquanto ela estiver parada."
        msg_aviso "Você ainda será cobrado pelo armazenamento EBS."
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao parar a instância $instance_id"
        echo "" >&2
        return 1
    fi
}
