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

# Função para listar Subnets em formato de tabela
listar_subnets() {
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                              SUBNETS DISPONÍVEIS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    # Obter e formatar a lista de Subnets
    aws ec2 describe-subnets \
        --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,VpcId]' \
        --output text | \
        awk 'BEGIN {
            printf "%-4s %-25s %-20s %-20s %-20s\n", "Nº", "SUBNET ID", "ZONA", "CIDR", "VPC ID" | "cat >&2"
            printf "%-4s %-25s %-20s %-20s %-20s\n", "----", "-------------------------", "--------------------", "--------------------", "--------------------" | "cat >&2"
        }
        {
            printf "%-4d %-25s %-20s %-20s %-20s\n", NR, $1, $2, $3, $4 | "cat >&2"
        }' 
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
}

# Função para obter Subnet ID por índice
obter_subnet_por_indice() {
    local indice="$1"
    
    aws ec2 describe-subnets \
        --query 'Subnets[*].SubnetId' \
        --output text | \
        awk -v idx="$indice" '{
            split($0, arr, "\t")
            if (idx > 0 && idx <= length(arr)) {
                print arr[idx]
            }
        }'
}

# Função para gerenciar Subnet (listar/selecionar)
gerenciar_subnet() {
    local subnet_id
    local escolha
    
    while true; do
        listar_subnets
        
        echo "Digite o número da Subnet que deseja usar:" >&2
        echo "" >&2
        
        read -p "Número da Subnet: " escolha >&2
        echo "" >&2
        
        if [[ "$escolha" =~ ^[0-9]+$ ]]; then
            subnet_id=$(obter_subnet_por_indice "$escolha")
            
            if [ -n "$subnet_id" ] && [ "$subnet_id" != "" ]; then
                echo "Subnet selecionada: $subnet_id" >&2
                if validar_confirmacao "Confirma esta seleção?"; then
                    echo "[OK] Subnet confirmada: $subnet_id" >&2
                    echo "" >&2
                    pausar 2
                    echo "$subnet_id"  # Retorna o ID
                    return 0
                fi
            else
                echo "[ERRO] Número inválido! Tente novamente." >&2
                echo "" >&2
                pausar 2
            fi
        else
            echo "[ERRO] Digite apenas números!" >&2
            echo "" >&2
            pausar 2
        fi
    done
}
