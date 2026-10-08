# ==============================================================================
# JEV / Laya — System-1 decision engine (ggmlc) exposto via MCP→OpenAPI (mcpo)
#
#   bin/laya                              binário ggmlc (build vulkan, roda em CPU)
#   models/laya_multilingual_q8_0.gguf    checkpoint multilíngue (~345 MB)
#   app/laya_mcp_server.py                MCP server (fuleinist/laya_mcp)
# ==============================================================================
FROM python:3.12-slim

# libvulkan1: o binário laya linka contra o loader Vulkan mesmo em modo CPU
# libgomp1: runtime OpenMP exigido pelo binário ggmlc
RUN apt-get update \
 && apt-get install -y --no-install-recommends libvulkan1 libgomp1 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# mcp 2.x renomeou streamablehttp_client -> streamable_http_client,
# McpError -> MCPError e Tool.inputSchema -> Tool.input_schema;
# mcpo 0.0.20 ainda usa os nomes antigos -> aliases/substituições.
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir "mcp>=2.0.0" mcpo uv \
 && sed -i \
      -e 's/from mcp.client.streamable_http import streamablehttp_client/from mcp.client.streamable_http import streamable_http_client as streamablehttp_client/' \
      -e 's/from mcp.shared.exceptions import McpError/from mcp.shared.exceptions import MCPError as McpError/' \
      /usr/local/lib/python3.12/site-packages/mcpo/main.py \
      /usr/local/lib/python3.12/site-packages/mcpo/utils/main.py \
 && sed -i 's/tool\.inputSchema/tool.input_schema/g' \
      /usr/local/lib/python3.12/site-packages/mcpo/main.py \
 && sed -i 's/result\.isError/result.is_error/g' \
      /usr/local/lib/python3.12/site-packages/mcpo/utils/main.py \
 && python -c "from mcpo.main import run; print('mcpo OK')"

WORKDIR /app
COPY app/laya_mcp_server.py /app/laya_mcp_server.py
COPY bin/laya /usr/local/bin/laya
COPY models/laya_multilingual_q8_0.gguf /models/laya_multilingual_q8_0.gguf

# CPU: a MX350 (sm_61) não tem build CUDA pré-compilado e tem só 2GB de VRAM.
# Em CPU o engine responde em ~0,1–0,7s por chamada — suficiente para o lab.
ENV LAYA_EXE=/usr/local/bin/laya \
    LAYA_MODEL=/models/laya_multilingual_q8_0.gguf \
    LAYA_DEVICE=cpu \
    LAYA_CUDA_GRAPH=0 \
    LAYA_CPU_FALLBACK=0

EXPOSE 8001

# mcpo converte o MCP stdio em OpenAPI/HTTP para o Open WebUI consumir
CMD ["mcpo", "--host", "0.0.0.0", "--port", "8001", "--", "python", "/app/laya_mcp_server.py"]
