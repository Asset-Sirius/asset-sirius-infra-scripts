#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE PARES DE CHAVES EC2
# ============================================================================

# Função para criar a pasta de pares de chaves
criar_pasta_par_chaves() {
    local pasta_par_chaves="$1"
    
    if [ ! -d "$pasta_par_chaves" ]; then
        msg_info "Criando pasta para armazenar pares de chaves..."
        mkdir -p "$pasta_par_chaves"
        if [ $? -eq 0 ]; then
            msg_sucesso "Pasta criada: $pasta_par_chaves"
        else
            msg_erro "Falha ao criar pasta: $pasta_par_chaves"
            return 1
        fi
    else
        msg_info "Pasta já existe: $pasta_par_chaves"
    fi
    echo "" >&2
    pausar 1
    return 0
}

# Função para verificar se o par de chaves já existe
verificar_par_chaves_existe() {
    local caminho_par_chaves="$1"
    
    if [ -f "$caminho_par_chaves" ]; then
        return 0  # Existe
    else
        return 1  # Não existe
    fi
}

# Função para criar par de chaves na AWS e salvar localmente
criar_par_chaves_aws() {
    local nome_par_chaves="$1"
    local caminho_par_chaves="$2"
    
    msg_info "Criando par de chaves '$nome_par_chaves' na AWS..."
    echo "" >&2
    pausar 1
    
    # Criar o par de chaves e salvar o conteúdo no arquivo
    aws ec2 create-key-pair \
        --key-name "$nome_par_chaves" \
        --query 'KeyMaterial' \
        --output text > "$caminho_par_chaves"
    
    if [ $? -eq 0 ]; then
        # Definir permissões corretas para o arquivo .pem
        chmod 400 "$caminho_par_chaves"
        
        msg_sucesso "Par de chaves criado com sucesso!"
        echo "" >&2
        msg_info "Detalhes:"
        echo "  - Nome: $nome_par_chaves" >&2
        echo "  - Arquivo: $caminho_par_chaves" >&2
        echo "  - Permissões: 400 (somente leitura para o dono)" >&2
        echo "" >&2
        pausar 2
        return 0
    else
        msg_erro "Falha ao criar o par de chaves na AWS"
        echo "" >&2
        # Remover arquivo se foi criado parcialmente
        [ -f "$caminho_par_chaves" ] && rm -f "$caminho_par_chaves"
        return 1
    fi
}

# Função para listar pares de chaves existentes na AWS
listar_pares_chaves_aws() {
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                      PARES DE CHAVES DISPONÍVEIS NA AWS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    # Obter lista de pares de chaves da AWS
    local chaves_aws=$(aws ec2 describe-key-pairs \
        --query 'KeyPairs[*].KeyName' \
        --output text 2>/dev/null)
    
    if [ -z "$chaves_aws" ]; then
        echo "  [INFO] Nenhum par de chaves encontrado na AWS." >&2
        echo "" >&2
        echo "═══════════════════════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        return 1
    fi
    
    # Listar os pares de chaves em formato de tabela
    echo "$chaves_aws" | tr '\t' '\n' | awk 'BEGIN {
        printf "%-4s %-60s\n", "Nº", "NOME DA CHAVE" | "cat >&2"
        printf "%-4s %-60s\n", "----", "------------------------------------------------------------" | "cat >&2"
    }
    {
        if ($0 != "") {
            printf "%-4d %-60s\n", NR, $0 | "cat >&2"
        }
    }'
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    return 0
}

# Função para listar pares de chaves locais (arquivos .pem na pasta)
listar_pares_chaves_locais() {
    local pasta_par_chaves="$1"
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                    PARES DE CHAVES DISPONÍVEIS LOCALMENTE" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    # Verificar se há arquivos .pem na pasta
    local arquivos_pem=$(find "$pasta_par_chaves" -maxdepth 1 -name "*.pem" 2>/dev/null)
    
    if [ -z "$arquivos_pem" ]; then
        echo "  [INFO] Nenhum par de chaves encontrado na pasta local." >&2
        echo "" >&2
        echo "═══════════════════════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        return 1
    fi
    
    # Listar os arquivos em formato de tabela
    echo "$arquivos_pem" | awk -v pasta="$pasta_par_chaves" 'BEGIN {
        printf "%-4s %-60s\n", "Nº", "NOME DO ARQUIVO" | "cat >&2"
        printf "%-4s %-60s\n", "----", "------------------------------------------------------------" | "cat >&2"
    }
    {
        # Extrair nome do arquivo
        split($0, path, "/")
        filename = path[length(path)]
        # Remover extensão .pem para mostrar apenas o nome
        nome = filename
        sub(/\.pem$/, "", nome)
        
        printf "%-4d %-60s\n", NR, nome | "cat >&2"
    }'
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    return 0
}

# Função para obter nome do par de chaves local por índice
obter_par_chaves_local_por_indice() {
    local pasta_par_chaves="$1"
    local indice="$2"
    
    find "$pasta_par_chaves" -maxdepth 1 -name "*.pem" 2>/dev/null | \
        awk -v idx="$indice" '{
            if (NR == idx) {
                split($0, path, "/")
                filename = path[length(path)]
                # Remover extensão .pem
                nome = filename
                sub(/\.pem$/, "", nome)
                print nome
                exit
            }
        }'
}

# Função para gerenciar par de chaves (selecionar existente ou criar novo)
gerenciar_par_chaves() {
    local pasta_par_chaves="$1"
    local nome_par_chaves
    local caminho_par_chaves
    local escolha
    
    # Criar a pasta se não existir
    criar_pasta_par_chaves "$pasta_par_chaves"
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    while true; do
        # Listar pares de chaves existentes na AWS
        echo "Verificando pares de chaves na AWS..." >&2
        listar_pares_chaves_aws
        
        # Listar pares de chaves existentes localmente
        listar_pares_chaves_locais "$pasta_par_chaves"
        local tem_chaves=$?
        
        echo "Escolha uma opção:" >&2
        if [ $tem_chaves -eq 0 ]; then
            echo "  [1-N] - Selecionar um par de chaves [LOCAL] existente pelo número" >&2
        fi
        echo "  [N] - Criar um novo par de chaves" >&2
        echo "" >&2
        
        read -p "Digite sua escolha: " escolha >&2
        echo "" >&2
        
        # Verificar se é um número (seleção de chave existente)
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ $tem_chaves -eq 0 ]; then
            nome_par_chaves=$(obter_par_chaves_local_por_indice "$pasta_par_chaves" "$escolha")
            
            if [ -n "$nome_par_chaves" ]; then
                caminho_par_chaves="$pasta_par_chaves/${nome_par_chaves}.pem"
                echo "Par de chaves selecionado: $nome_par_chaves" >&2
                if validar_confirmacao "Confirma esta seleção?"; then
                    msg_sucesso "Usando par de chaves: $nome_par_chaves"
                    echo "" >&2
                    pausar 2
                    echo "$nome_par_chaves"  # Retorna apenas o nome
                    return 0
                fi
            else
                msg_erro "Número inválido! Tente novamente."
                echo "" >&2
                pausar 2
            fi
        elif [[ "$escolha" == "N" ]] || [[ "$escolha" == "n" ]]; then
            # Criar novo par de chaves
            echo "Criando um novo par de chaves..." >&2
            echo "" >&2
            pausar 1
            
            nome_par_chaves=$(obter_input_validado "Digite o nome do par de chaves que deseja criar:")
            caminho_par_chaves="$pasta_par_chaves/${nome_par_chaves}.pem"
            
            # Verificar se já existe localmente
            if verificar_par_chaves_existe "$caminho_par_chaves"; then
                msg_aviso "Já existe um arquivo com este nome na pasta local!"
                echo "  - Arquivo: $caminho_par_chaves" >&2
                echo "" >&2
                
                if validar_confirmacao "Deseja reutilizar este par de chaves existente?"; then
                    msg_sucesso "Reutilizando par de chaves: $nome_par_chaves"
                    echo "" >&2
                    pausar 2
                    echo "$nome_par_chaves"
                    return 0
                else
                    msg_info "Por favor, escolha outro nome."
                    echo "" >&2
                    pausar 1
                    continue
                fi
            fi
            
            # Criar novo par de chaves na AWS
            if criar_par_chaves_aws "$nome_par_chaves" "$caminho_par_chaves"; then
                if verificar_par_chaves_existe "$caminho_par_chaves"; then
                    msg_sucesso "Par de chaves validado e pronto para uso!"
                    echo "" >&2
                    pausar 2
                    echo "$nome_par_chaves"
                    return 0
                else
                    msg_erro "Falha na validação do par de chaves criado"
                    echo "" >&2
                    pausar 2
                    return 1
                fi
            else
                msg_erro "Não foi possível criar o par de chaves"
                echo "" >&2
                if validar_confirmacao "Deseja tentar novamente?"; then
                    continue
                else
                    return 1
                fi
            fi
        else
            msg_erro "Opção inválida! Digite um número ou 'N'."
            echo "" >&2
            pausar 2
        fi
    done
}
