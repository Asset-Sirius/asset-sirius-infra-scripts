#!/bin/bash

# ============================================================================
# SCRIPT DE CRIAÇÃO DE INSTÂNCIA EC2 NA AWS
# ============================================================================
# Descrição: Script automatizado para criação de instâncias EC2
# Autor: Asset Sirius Team
# Data: $(date +%Y-%m-%d)
# ============================================================================

# Obter o diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importar funções auxiliares
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validacao.sh"
source "$SCRIPT_DIR/lib/aws_helpers.sh"

# ============================================================================
# INÍCIO DO SCRIPT
# ============================================================================
exibir_banner

echo "Bem vindo a criação de uma instância EC2 na AWS, para isso, siga os passos abaixo:" >&2
separador

# ----------------------------------------------------------------------------
# ETAPA 1: Nome da Instância
# ----------------------------------------------------------------------------
titulo_etapa "1" "Escolha o nome da sua instância EC2"
separador
nome_instancia=$(obter_input_validado "Digite o nome da instância EC2 que deseja criar:")
msg_sucesso "Nome da instância confirmado: $nome_instancia"
separador
pausar 2

# ----------------------------------------------------------------------------
# ETAPA 2: Criação/Seleção do Par de Chaves
# ----------------------------------------------------------------------------
echo "Preparando próxima etapa..." >&2
pausar 2

titulo_etapa "2" "Criação do par de chaves para acesso à instância EC2"
separador
pausar 1

# Definir pasta para pares de chaves
PASTA_PAR_CHAVES="$HOME/Downloads/par de chaves EC2"

nome_par_chaves=$(gerenciar_par_chaves "$PASTA_PAR_CHAVES")

if [ $? -ne 0 ] || [ -z "$nome_par_chaves" ]; then
    msg_erro "Falha ao criar/selecionar o par de chaves"
    exit 1
fi

# ----------------------------------------------------------------------------
# ETAPA 3: Grupo de Segurança
# ----------------------------------------------------------------------------
echo "Preparando próxima etapa..." >&2
pausar 2
separador

titulo_etapa "3" "Configuração do Grupo de Segurança para a instância EC2"
separador
pausar 1

security_group_id=$(gerenciar_security_group)

if [ $? -ne 0 ] || [ -z "$security_group_id" ]; then
    msg_erro "Falha ao criar ou selecionar o Security Group"
    exit 1
fi

# ----------------------------------------------------------------------------
# ETAPA 4: Seleção da Subnet
# ----------------------------------------------------------------------------
echo "Preparando próxima etapa..." >&2
pausar 2
separador

titulo_etapa "4" "Seleção da Subnet (Rede) para a instância EC2"
separador
pausar 1

subnet_id=$(gerenciar_subnet)

if [ $? -ne 0 ] || [ -z "$subnet_id" ]; then
    msg_erro "Falha ao selecionar a Subnet"
    exit 1
fi

# ----------------------------------------------------------------------------
# ETAPA 5: Criação da Instância EC2
# ----------------------------------------------------------------------------
echo "Preparando próxima etapa..." >&2
pausar 2
separador

titulo_etapa "5" "Criação da Instância EC2"
separador
pausar 1

# Configurações fixas da instância
IMAGE_ID='ami-0b6c6ebed2801a5cb'
INSTANCE_TYPE='t3.small'
COUNT='1'
VOLUME_SIZE='8'
VOLUME_TYPE='gp3'
DEVICE_NAME='/dev/sda1'

separador
msg_info "Configurações da instância:"
echo "  - Nome: $nome_instancia" >&2
echo "  - AMI: $IMAGE_ID" >&2
echo "  - Tipo: $INSTANCE_TYPE" >&2
echo "  - Par de chaves: $nome_par_chaves" >&2
echo "  - Security Group: $security_group_id" >&2
echo "  - Subnet: $subnet_id" >&2
echo "  - Volume: ${VOLUME_SIZE}GB ($VOLUME_TYPE)" >&2
separador
pausar 2

if validar_confirmacao "Deseja criar a instância EC2 com estas configurações?"; then
    echo "Iniciando criação da instância..." >&2
    separador
    pausar 1
    
    instance_id=$(criar_instancia \
        "$nome_instancia" \
        "$IMAGE_ID" \
        "$INSTANCE_TYPE" \
        "$nome_par_chaves" \
        "$subnet_id" \
        "$DEVICE_NAME" \
        "$COUNT" \
        "$security_group_id" \
        "$VOLUME_SIZE" \
        "$VOLUME_TYPE")
    
    if [ $? -eq 0 ] && [ -n "$instance_id" ]; then
        separador
        echo "═══════════════════════════════════════════════════════════════════════" >&2
        echo "                    [OK] INSTÂNCIA CRIADA COM SUCESSO!" >&2
        echo "═══════════════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        
        # Buscar IP público da instância
        ip_publico=$(obter_ip_publico_instancia "$instance_id")
        
        msg_info "Detalhes da instância:"
        echo "  - Instance ID: $instance_id" >&2
        echo "  - Nome: $nome_instancia" >&2
        echo "  - Tipo: $INSTANCE_TYPE" >&2
        echo "  - Região: $(aws configure get region 2>/dev/null || echo 'default')" >&2
        
        if [ -n "$ip_publico" ]; then
            echo "  - IP Público: $ip_publico" >&2
        fi
        
        separador
        echo "Dica: Aguarde alguns minutos para a instância inicializar completamente." >&2
        separador
        
        # Exibir comandos de acesso
        echo "═══════════════════════════════════════════════════════════════════════" >&2
        echo "                          COMANDOS ÚTEIS" >&2
        echo "═══════════════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        
        # Definir caminho completo do par de chaves
        CAMINHO_PAR_CHAVES="$PASTA_PAR_CHAVES/${nome_par_chaves}.pem"
        
        if [ -n "$ip_publico" ]; then
            echo "[INFO] Para conectar via SSH na instância:" >&2
            echo "" >&2
            echo "   cd \"$PASTA_PAR_CHAVES\"" >&2
            echo "   ssh -i \"$CAMINHO_PAR_CHAVES\" ubuntu@$ip_publico" >&2
            echo "" >&2
        else
            echo "[INFO] Para conectar via SSH na instância (após obter o IP público):" >&2
            echo "" >&2
            echo "   cd \"$PASTA_PAR_CHAVES\"" >&2
            echo "   ssh -i \"$CAMINHO_PAR_CHAVES\" ubuntu@<IP_PUBLICO>" >&2
            echo "" >&2
            echo "   [INFO] Para obter o IP público, execute:" >&2
            echo "   aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text" >&2
            echo "" >&2
        fi
        
        separador
        echo "[INFO] Nota: O usuário padrão para Ubuntu é 'ubuntu'" >&2
        echo "[INFO] O arquivo .pem já possui as permissões corretas (400)" >&2
        separador
        echo "═══════════════════════════════════════════════════════════════════════" >&2
        separador
    else
        msg_erro "Falha ao criar a instância EC2"
        exit 1
    fi
else
    echo "[CANCELADO] Criação da instância cancelada pelo usuário." >&2
    separador
    exit 0
fi
