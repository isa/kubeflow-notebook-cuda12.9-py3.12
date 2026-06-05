# =============================================================================
# Kubeflow Notebook Server
# Base:     nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04
# Python:   3.12 (default), 3.13, 3.14  (via mise)
# Node.js:  26 (default), 25, 24         (via mise)
# uv:       latest                        (via mise)
# =============================================================================

FROM nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04

# -----------------------------------------------------------------------------
# Labels
# -----------------------------------------------------------------------------
LABEL maintainer="your-team@example.com" \
      cuda="12.9.1" \
      cudnn="9" \
      description="Kubeflow Notebook Server — CUDA 12.9 · Python 3.12/3.13/3.14 · Node 24/25/26 · uv"

# -----------------------------------------------------------------------------
# Build arguments
# -----------------------------------------------------------------------------
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_PREFIX="/"

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # mise global tool dir — world-readable so all users get the tools
    MISE_DATA_DIR="/usr/local/mise" \
    MISE_CONFIG_DIR="/usr/local/mise" \
    MISE_CACHE_DIR="/usr/local/mise/cache" \
    MISE_INSTALL_PATH="/usr/local/bin/mise" \
    # Shims path baked into the image ENV so it survives into runtime shells
    PATH="/usr/local/mise/shims:/usr/local/bin:${PATH}" \
    # Kubeflow
    NB_PREFIX=${NB_PREFIX} \
    NB_USER=${NB_USER} \
    NB_UID=${NB_UID} \
    HOME="/home/${NB_USER}"

# -----------------------------------------------------------------------------
# Drop the NVIDIA apt repo — CUDA is already baked into the base image.
# Prevents DNS failures on restricted / VPN networks.
# -----------------------------------------------------------------------------
RUN rm -f /etc/apt/sources.list.d/cuda*.list \
          /etc/apt/sources.list.d/nvidia*.list \
 && apt-get clean

# -----------------------------------------------------------------------------
# System packages — build deps for mise-compiled Python
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    unzip \
    zip \
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    liblzma-dev \
    zlib1g-dev \
    libncurses5-dev \
    libgdbm-dev \
    libnss3-dev \
    tini \
    sudo \
    openssh-client \
    openssh-server \
    autossh \
    jq \
    vim \
    htop \
    tmux \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# mise — install all Python + Node versions, set 3.12 / Node 26 as defaults
# -----------------------------------------------------------------------------
RUN curl https://mise.run | sh \
 && mise install python@3.12 python@3.13 python@3.14 \
                 node@24 node@25 node@26 \
                 uv@latest \
 && mise use --global python@3.12 node@26 uv@latest \
 && mise reshim

# -----------------------------------------------------------------------------
# Symlink all tools into /usr/local/bin — survives for all users at runtime
# regardless of whether mise shims are on PATH
# -----------------------------------------------------------------------------
RUN ln -sf /usr/local/mise/shims/python     /usr/local/bin/python     \
 && ln -sf /usr/local/mise/shims/python     /usr/local/bin/python3    \
 && ln -sf /usr/local/mise/shims/python3.12 /usr/local/bin/python3.12 \
 && ln -sf /usr/local/mise/shims/python3.13 /usr/local/bin/python3.13 \
 && ln -sf /usr/local/mise/shims/python3.14 /usr/local/bin/python3.14 \
 && ln -sf /usr/local/mise/shims/node       /usr/local/bin/node       \
 && ln -sf /usr/local/mise/shims/npm        /usr/local/bin/npm        \
 && ln -sf /usr/local/mise/shims/npx        /usr/local/bin/npx        \
 && ln -sf /usr/local/mise/shims/uv         /usr/local/bin/uv         \
 && ln -sf /usr/local/mise/shims/uvx        /usr/local/bin/uvx

# -----------------------------------------------------------------------------
# Non-root user (Kubeflow convention: jovyan / UID 1000)
# -----------------------------------------------------------------------------
RUN existing=$(getent passwd ${NB_UID} | cut -d: -f1) \
 && if [ -n "$existing" ] && [ "$existing" != "${NB_USER}" ]; then userdel -r "$existing" 2>/dev/null || true; fi \
 && if ! id -u ${NB_USER} >/dev/null 2>&1; then useradd -m -s /bin/bash -u ${NB_UID} ${NB_USER}; fi \
 && mkdir -p /home/${NB_USER}/.local/bin \
 && echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
 && chown -R ${NB_USER}:${NB_USER} /home/${NB_USER}

# -----------------------------------------------------------------------------
# Python packages via uv — targets mise's Python 3.12, no PEP 668 issues
# Then symlink jupyter into /usr/local/bin so it's found at runtime
# -----------------------------------------------------------------------------
RUN uv pip install --system \
    jupyterlab \
    notebook \
    ipywidgets \
    numpy \
    pandas \
    matplotlib \
    scikit-learn \
    torch \
    tqdm \
    requests \
    httpx \
 && SCRIPTS=$(python -c "import sysconfig; print(sysconfig.get_path('scripts'))") \
 && ln -sf "${SCRIPTS}/jupyter"         /usr/local/bin/jupyter     \
 && ln -sf "${SCRIPTS}/jupyter-lab"     /usr/local/bin/jupyter-lab \
 && ln -sf "${SCRIPTS}/jupyter-server"  /usr/local/bin/jupyter-server

# -----------------------------------------------------------------------------
# Kubeflow: expose port and set entrypoint
# Use absolute path for jupyter — bulletproof regardless of PATH at runtime
# -----------------------------------------------------------------------------
USER ${NB_USER}
WORKDIR ${HOME}
EXPOSE 8888

ENTRYPOINT ["tini", "--"]
CMD ["sh", "-c", \
     "/usr/local/bin/jupyter lab \
       --ip=0.0.0.0 \
       --port=8888 \
       --no-browser \
       --allow-root \
       --NotebookApp.token='' \
       --NotebookApp.password='' \
       --NotebookApp.allow_origin='*' \
       --NotebookApp.base_url=${NB_PREFIX}"]
