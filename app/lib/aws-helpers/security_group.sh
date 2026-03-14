#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE SECURITY GROUPS
# ============================================================================

# Função para criar Security Group sem regras (genérico)
criar_security_group_custom() {
    local nome_sg="$1"
    local descricao="$2"
    local vpc_id="$3"

    msg_info "Criando Security Group '$nome_sg'..."

    local sg_id=$(aws ec2 create-security-group \
        --group-name "$nome_sg" \
        --description "$descricao" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$sg_id" ]; then
        echo "$sg_id"
        return 0
    else
        msg_erro "Falha ao criar Security Group"
        return 1
    fi
}

# Função para adicionar regra de entrada (ingress) a um Security Group
adicionar_regra_ingress() {
    local sg_id="$1"
    local protocol="$2"
    local port="$3"
    local cidr="$4"

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$port" \
        --cidr "$cidr" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        return 0
    else
        msg_aviso "Regra pode já existir: porta $port em $sg_id"
        return 1
    fi
}

# Função para deletar Security Group
deletar_security_group() {
    local sg_id="$1"

    msg_info "Deletando Security Group '$sg_id'..."
    aws ec2 delete-security-group --group-id "$sg_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Security Group deletado!"
        return 0
    else
        msg_erro "Falha ao deletar Security Group"
        return 1
    fi
}


