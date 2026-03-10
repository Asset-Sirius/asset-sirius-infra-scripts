#!/bin/bash

# ============================================================================
# FUNÇÕES DE VALIDAÇÃO E INPUT
# ============================================================================

# Função para validar confirmação y/n
validar_confirmacao() {
    local mensagem="$1"
    local resposta
    
    read -p "$mensagem (y/n): " resposta >&2
    echo "" >&2
    
    if [[ "$resposta" == "y" || "$resposta" == "Y" ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Função para obter input com validação
obter_input_validado() {
    local prompt="$1"
    local valor
    
    while true; do
        echo "$prompt" >&2
        read valor
        echo "" >&2
        
        if [ -n "$valor" ]; then
            echo "Valor escolhido: $valor" >&2
            if validar_confirmacao "Confirma esse valor?"; then
                echo "$valor"
                return 0
            else
                echo "Ok, vamos tentar novamente..." >&2
                echo "" >&2
            fi
        else
            echo "[ERRO] Valor não pode ser vazio!" >&2
            echo "" >&2
        fi
    done
}

# Função para obter senha com validação de tamanho mínimo
obter_senha_validada() {
    local prompt="$1"
    local min_length="${2:-8}"
    local valor

    while true; do
        echo "$prompt" >&2
        read -s valor
        echo "" >&2

        if [ -z "$valor" ]; then
            echo "[ERRO] A senha não pode ser vazia!" >&2
            echo "" >&2
            continue
        fi

        if [ ${#valor} -lt $min_length ]; then
            echo "[ERRO] A senha deve ter no mínimo $min_length caracteres! (digitado: ${#valor})" >&2
            echo "" >&2
            continue
        fi

        echo "Senha digitada com ${#valor} caracteres." >&2
        if validar_confirmacao "Confirma essa senha?"; then
            echo "$valor"
            return 0
        else
            echo "Ok, vamos tentar novamente..." >&2
            echo "" >&2
        fi
    done
}


