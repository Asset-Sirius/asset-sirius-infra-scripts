#!/bin/bash

# ============================================================================
# SCRIPT DE EXCLUSÃO DE INSTÂNCIA EC2 NA AWS
# ============================================================================
# Descrição: Script automatizado para encerrar instâncias EC2
# Autor: Asset Sirius Team
# Data: $(date +%Y-%m-%d)
# ============================================================================

# Obter o diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importar funções auxiliares
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/aws_helpers.sh"

# ============================================================================
# INÍCIO DO SCRIPT
# ============================================================================
exibir_banner

echo "Bem-vindo ao sistema de gerenciamento de instâncias EC2 na AWS!" >&2
echo "Este script permite encerrar ou parar instâncias existentes." >&2
separador
pausar 2

# ----------------------------------------------------------------------------
# ETAPA 1: Listar Instâncias Disponíveis
# ----------------------------------------------------------------------------
echo "═══════════════════════════════════════════════════════════════════════════════" >&2
echo "                  ETAPA 1: SELECIONAR INSTÂNCIA" >&2
echo "═══════════════════════════════════════════════════════════════════════════════" >&2
separador

listar_instancias_ec2

if [ $? -ne 0 ]; then
    msg_erro "Nenhuma instância disponível para gerenciar."
    exit 1
fi

pausar 1

# ----------------------------------------------------------------------------
# ETAPA 2: Selecionar Instância
# ----------------------------------------------------------------------------
read -p "Digite o número da instância que deseja gerenciar (ou 0 para sair): " escolha >&2
echo "" >&2

if [ "$escolha" == "0" ]; then
    msg_info "Operação cancelada pelo usuário."
    exit 0
fi

# Validar entrada
if ! [[ "$escolha" =~ ^[0-9]+$ ]]; then
    msg_erro "Entrada inválida. Por favor, digite um número."
    exit 1
fi

# Obter Instance ID
instance_id=$(obter_instance_id_por_indice "$escolha")

if [ -z "$instance_id" ] || [ "$instance_id" == "None" ]; then
    msg_erro "Instância não encontrada. Verifique o número digitado."
    exit 1
fi

msg_sucesso "Instância selecionada: $instance_id"
separador
pausar 2

# ----------------------------------------------------------------------------
# ETAPA 3: Exibir Detalhes e Escolher Ação
# ----------------------------------------------------------------------------
exibir_detalhes_instancia "$instance_id"
pausar 2

echo "═══════════════════════════════════════════════════════════════════════════════" >&2
echo "                  ESCOLHA A AÇÃO DESEJADA" >&2
echo "═══════════════════════════════════════════════════════════════════════════════" >&2
echo "" >&2
echo "1) PARAR a instância (pode ser reiniciada depois)" >&2
echo "2) ENCERRAR a instância (PERMANENTE - não pode ser desfeito)" >&2
echo "0) Cancelar e sair" >&2
echo "" >&2
echo "═══════════════════════════════════════════════════════════════════════════════" >&2
echo "" >&2

read -p "Digite sua escolha: " acao >&2
echo "" >&2

# ----------------------------------------------------------------------------
# ETAPA 4: Executar Ação
# ----------------------------------------------------------------------------
case $acao in
    1)
        if confirmar_acao "Você está prestes a PARAR a instância $instance_id."; then
            parar_instancia "$instance_id"
            if [ $? -eq 0 ]; then
                separador
                msg_sucesso "Operação concluída com sucesso!"
            fi
        fi
        ;;
    2)
        if confirmar_acao "⚠️  ATENÇÃO: Você está prestes a ENCERRAR a instância $instance_id. Esta ação é IRREVERSÍVEL!"; then
            encerrar_instancia "$instance_id"
            if [ $? -eq 0 ]; then
                separador
                msg_sucesso "Operação concluída com sucesso!"
                separador
                msg_info "A instância será completamente removida e não poderá ser recuperada."
            fi
        fi
        ;;
    0)
        msg_info "Operação cancelada pelo usuário."
        exit 0
        ;;
    *)
        msg_erro "Opção inválida."
        exit 1
        ;;
esac

separador
echo "Script finalizado." >&2
separador
