#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE SUBNETS
# ============================================================================

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
