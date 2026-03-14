#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE SUBNETS
# ============================================================================

# Função para criar Subnet
criar_subnet() {
    local vpc_id="$1"
    local cidr_block="$2"
    local az="$3"
    local nome="$4"

    msg_info "Criando Subnet '$nome' ($cidr_block) na zona $az..."
    pausar 1

    local subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$cidr_block" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$nome}]" \
        --query 'Subnet.SubnetId' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$subnet_id" ]; then
        msg_sucesso "Subnet criada: $subnet_id"
        echo "" >&2
        echo "$subnet_id"
        return 0
    else
        msg_erro "Falha ao criar Subnet"
        return 1
    fi
}

# Função para habilitar auto-assign de IP público em uma Subnet
habilitar_ip_publico_subnet() {
    local subnet_id="$1"

    msg_info "Habilitando auto-assign de IP público na Subnet '$subnet_id'..."

    aws ec2 modify-subnet-attribute \
        --subnet-id "$subnet_id" \
        --map-public-ip-on-launch > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Auto-assign de IP público habilitado!"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao habilitar auto-assign de IP público"
        return 1
    fi
}

# Função para deletar Subnet
deletar_subnet() {
    local subnet_id="$1"

    msg_info "Deletando Subnet '$subnet_id'..."
    aws ec2 delete-subnet --subnet-id "$subnet_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Subnet deletada!"
        return 0
    else
        msg_erro "Falha ao deletar Subnet"
        return 1
    fi
}


