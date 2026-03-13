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

# Função para aguardar SSH disponível e enviar chave .pem via SCP para a instância
# Uso: aguardar_ssh_e_enviar_chave <ip> <caminho_chave_pem> <nome_chave>
aguardar_ssh_e_enviar_chave() {
    local ip="$1"
    local caminho_chave="$2"
    local nome_chave="$3"
    local timeout=180
    local intervalo=10
    local elapsed=0
    local ssh_pronto=false

    msg_info "Aguardando instância ($ip) estar acessível via SSH..."

    while [ $elapsed -lt $timeout ]; do
        if ssh -i "$caminho_chave" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            ubuntu@"$ip" "exit" 2>/dev/null; then
            ssh_pronto=true
            break
        fi
        msg_info "SSH ainda indisponível... ($elapsed/$timeout segundos)"
        sleep $intervalo
        elapsed=$((elapsed + intervalo))
    done

    if [ "$ssh_pronto" = false ]; then
        msg_aviso "Instância não ficou acessível via SSH no tempo esperado."
        msg_aviso "Execute manualmente após a instância inicializar:"
        echo "  scp -i \"$caminho_chave\" \"$caminho_chave\" ubuntu@$ip:/home/ubuntu/.ssh/${nome_chave}.pem" >&2
        return 1
    fi

    msg_info "SSH disponível! Enviando ${nome_chave}.pem via SCP..."
    scp -i "$caminho_chave" \
        -o StrictHostKeyChecking=no \
        "$caminho_chave" \
        ubuntu@"$ip":/home/ubuntu/.ssh/"${nome_chave}.pem"

    if [ $? -eq 0 ]; then
        ssh -i "$caminho_chave" \
            -o StrictHostKeyChecking=no \
            ubuntu@"$ip" \
            "chmod 400 /home/ubuntu/.ssh/${nome_chave}.pem" 2>/dev/null
        msg_sucesso "Chave enviada para /home/ubuntu/.ssh/${nome_chave}.pem"
        return 0
    else
        msg_erro "Falha ao enviar a chave via SCP."
        msg_aviso "Execute manualmente:"
        echo "  scp -i \"$caminho_chave\" \"$caminho_chave\" ubuntu@$ip:/home/ubuntu/.ssh/${nome_chave}.pem" >&2
        return 1
    fi
}


