from __future__ import annotations

from pathlib import Path

from ingestao_dados_functions import (
    diretorio_tem_arquivos,
    executar_download,
)


DIRETORIO_SAIDA = Path("dados_cvm")
SOBRESCREVER = False
TIMEOUT_SEGUNDOS = 120
MODO_CARGA = "auto"


def main() -> None:
    """Executa a ingestão com configuração fixa definida no próprio arquivo.

    Args:
        Nenhum.

    Returns:
        None. A função valida a configuração fixa e inicia o download.
    """
    if MODO_CARGA not in {"auto", "incremental", "historica"}:
        raise ValueError("MODO_CARGA inválido. Use: auto, incremental ou historica.")

    diretorio_saida = DIRETORIO_SAIDA

    if MODO_CARGA == "auto":
        tipo_carga = "incremental" if diretorio_tem_arquivos(diretorio_saida) else "historica"
    else:
        tipo_carga = MODO_CARGA

    executar_download(
        diretorio_saida=diretorio_saida,
        sobrescrever=SOBRESCREVER,
        timeout=TIMEOUT_SEGUNDOS,
        tipo_carga=tipo_carga,
    )


if __name__ == "__main__":
    main()