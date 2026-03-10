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

# Função para criar Security Group com regras HTTP/HTTPS
criar_security_group_web() {
    local nome_sg="$1"
    local descricao="$2"
    local vpc_id="$3"
    
    echo "Criando Security Group '$nome_sg'..." >&2
    
    # Criar o Security Group
    local sg_id=$(aws ec2 create-security-group \
        --group-name "$nome_sg" \
        --description "$descricao" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text)
    
    if [ $? -eq 0 ]; then
        echo "[OK] Security Group criado: $sg_id" >&2
        echo "" >&2
        pausar 1
        
        # Adicionar regra para HTTP (porta 80)
        echo "Adicionando regra HTTP (porta 80)..." >&2
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 > /dev/null 2>&1
        
        # Adicionar regra para HTTPS (porta 443)
        echo "Adicionando regra HTTPS (porta 443)..." >&2
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0 > /dev/null 2>&1
        
        # Adicionar regra para porta 8080
        echo "Adicionando regra para porta 8080..." >&2
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 8080 \
            --cidr 0.0.0.0/0 > /dev/null 2>&1
        
        # Adicionar regra para SSH (porta 22)
        echo "Adicionando regra SSH (porta 22)..." >&2
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 > /dev/null 2>&1
        
        echo "[OK] Regras de segurança configuradas!" >&2
        echo "" >&2
        pausar 1
        
        echo "$sg_id"  # Retorna apenas o ID do Security Group
        return 0
    else
        echo "[ERRO] Erro ao criar Security Group" >&2
        echo "" >&2
        return 1
    fi
}

# Função para listar Security Groups em formato de tabela
listar_security_groups() {
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                         SECURITY GROUPS DISPONÍVEIS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    # Obter e formatar a lista de Security Groups
    aws ec2 describe-security-groups \
        --query 'SecurityGroups[*].[GroupId,GroupName,Description,VpcId]' \
        --output text | \
        awk 'BEGIN {
            printf "%-4s %-25s %-35s %-25s\n", "Nº", "GROUP ID", "NOME", "DESCRIÇÃO" | "cat >&2"
            printf "%-4s %-25s %-35s %-25s\n", "----", "-------------------------", "-----------------------------------", "-------------------------" | "cat >&2"
        }
        {
            printf "%-4d %-25s %-35s %-25s\n", NR, $1, $2, $3 | "cat >&2"
        }' 
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
}

# Função para obter Security Group ID por índice
obter_sg_por_indice() {
    local indice="$1"
    
    aws ec2 describe-security-groups \
        --query 'SecurityGroups[*].GroupId' \
        --output text | \
        awk -v idx="$indice" '{
            split($0, arr, "\t")
            if (idx > 0 && idx <= length(arr)) {
                print arr[idx]
            }
        }'
}

# Função para gerenciar Security Group (listar/selecionar/criar)
gerenciar_security_group() {
    local sg_id
    local escolha
    local vpc_id
    
    while true; do
        listar_security_groups
        
        echo "Escolha uma opção:" >&2
        echo "  [1-N] - Selecionar um Security Group existente pelo número" >&2
        echo "  [N] - Criar um novo Security Group" >&2
        echo "" >&2
        
        read -p "Digite o número do Security Group ou 'N' para criar novo: " escolha >&2
        echo "" >&2
        
        if [[ "$escolha" =~ ^[0-9]+$ ]]; then
            # Usuário escolheu um número
            sg_id=$(obter_sg_por_indice "$escolha")
            
            if [ -n "$sg_id" ] && [ "$sg_id" != "" ]; then
                echo "Security Group selecionado: $sg_id" >&2
                if validar_confirmacao "Confirma esta seleção?"; then
                    echo "[OK] Security Group confirmado: $sg_id" >&2
                    echo "" >&2
                    pausar 2
                    echo "$sg_id"  # Retorna o ID
                    return 0
                fi
            else
                echo "[ERRO] Número inválido! Tente novamente." >&2
                echo "" >&2
                pausar 2
            fi
        elif [[ "$escolha" == "N" ]] || [[ "$escolha" == "n" ]]; then
            # Criar novo Security Group
            echo "Criando um novo Security Group..." >&2
            echo "" >&2
            pausar 1
            
            # Obter VPC padrão
            vpc_id=$(obter_vpc_padrao)
            if [ $? -ne 0 ] || [ -z "$vpc_id" ]; then
                echo "[ERRO] Erro: Não foi possível encontrar a VPC padrão" >&2
                read -p "Digite o VPC ID manualmente: " vpc_id >&2
                echo "" >&2
            else
                echo "[OK] VPC padrão encontrada: $vpc_id" >&2
                echo "" >&2
            fi
            
            local nome_sg=$(obter_input_validado "Digite o nome do Security Group:")
            local descricao_sg=$(obter_input "Digite a descrição do Security Group:")
            
            sg_id=$(criar_security_group_web "$nome_sg" "$descricao_sg" "$vpc_id")
            
            if [ $? -eq 0 ] && [ -n "$sg_id" ]; then
                echo "[OK] Security Group criado e configurado com sucesso!" >&2
                echo "  ID: $sg_id" >&2
                echo "" >&2
                pausar 2
                echo "$sg_id"  # Retorna o ID
                return 0
            else
                echo "[ERRO] Falha ao criar Security Group. Tente novamente." >&2
                echo "" >&2
                pausar 2
            fi
        else
            echo "[ERRO] Opção inválida! Digite um número ou 'N'." >&2
            echo "" >&2
            pausar 2
        fi
    done
}
