# =============================================================================
# Kubeflow Notebook Server
# Base:     nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04
# Tools:    mise (users install python/node/uv via mise at runtime)
# =============================================================================

FROM nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04

# -----------------------------------------------------------------------------
# Labels
# -----------------------------------------------------------------------------
LABEL maintainer="your-team@example.com" \
      cuda="12.9.1" \
      cudnn="9" \
      description="Kubeflow Notebook Server — CUDA 12.9 · mise · zsh · docker"

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
    MISE_DATA_DIR="/usr/local/mise" \
    MISE_CONFIG_DIR="/usr/local/mise" \
    MISE_CACHE_DIR="/usr/local/mise/cache" \
    MISE_INSTALL_PATH="/usr/local/bin/mise" \
    PATH="/usr/local/mise/shims:/usr/local/bin:${PATH}" \
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
# System packages
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    unzip \
    zip \
    # Build tools (needed by mise when compiling Python/Node from source)
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
    # Runtime
    tini \
    sudo \
    openssh-client \
    openssh-server \
    autossh \
    jq \
    vim \
    htop \
    tmux \
    zsh \
    docker.io \
    btop \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# mise — installed globally, ready to use. No tools pre-installed.
# Users run: mise install python@3.12 node@26 uv@latest
# -----------------------------------------------------------------------------
RUN curl https://mise.run | sh

# -----------------------------------------------------------------------------
# Rust + Cargo + CLI tools (eza, dust, dysk, xt)
# Install rustup non-interactively, then use cargo to build tools
# -----------------------------------------------------------------------------
ENV RUSTUP_HOME="/usr/local/rustup" \
    CARGO_HOME="/usr/local/cargo" \
    PATH="/usr/local/cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path \
 && cargo install eza \
 && cargo install du-dust \
 && cargo install dysk \
 && cargo install xh \
 && cargo install ripgrep \
 && cargo install lesser \
 && cargo install bat \
 && rm -rf /usr/local/cargo/registry /usr/local/cargo/git

# -----------------------------------------------------------------------------
# Non-root user (Kubeflow convention: jovyan / UID 1000)
# -----------------------------------------------------------------------------
RUN existing=$(getent passwd ${NB_UID} | cut -d: -f1) \
 && if [ -n "$existing" ] && [ "$existing" != "${NB_USER}" ]; then userdel -r "$existing" 2>/dev/null || true; fi \
 && if ! id -u ${NB_USER} >/dev/null 2>&1; then useradd -m -s /bin/zsh -u ${NB_UID} ${NB_USER}; fi \
 && mkdir -p /home/${NB_USER}/.local/bin \
 && echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
 && groupadd -f docker \
 && usermod -aG docker ${NB_USER} \
 && chown -R ${NB_USER}:${NB_USER} /home/${NB_USER}

# -----------------------------------------------------------------------------
# oh-my-zsh for jovyan + mise hook in .zshrc
# -----------------------------------------------------------------------------
RUN su - ${NB_USER} -c \
    'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' \
 && echo 'export PATH=/usr/local/cargo/bin:/usr/local/mise/shims:/usr/local/bin:$PATH' >> /home/${NB_USER}/.zshrc \
 && echo 'eval "$(mise activate zsh)"' >> /home/${NB_USER}/.zshrc \
 && echo 'export SHELL=/bin/zsh' >> /home/${NB_USER}/.zshrc \
 && sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="minimal"/' /home/${NB_USER}/.zshrc \
 && echo 'alias ls="eza --icons"' >> /home/${NB_USER}/.zshrc \
 && echo 'alias l="eza -xa --icons --group-directories-first"' >> /home/${NB_USER}/.zshrc \
 && echo 'alias ll="eza -lTa --icons --group-directories-first --level=1"' >> /home/${NB_USER}/.zshrc \
 && echo 'alias lll="eza -lTa --icons --group-directories-first --level=2"' >> /home/${NB_USER}/.zshrc \
 && echo 'alias top="btop"' >> /home/${NB_USER}/.zshrc \
 && echo 'alias less="bat"' >> /home/${NB_USER}/.zshrc

# Tell JupyterLab terminals to use zsh
RUN mkdir -p /etc/jupyter \
 && echo 'c.ServerApp.terminado_settings = {"shell_command": ["/bin/zsh"]}' >> /etc/jupyter/jupyter_server_config.py

# -----------------------------------------------------------------------------
# Install JupyterLab via pip (system Python from base image) so the notebook
# server can start. Users manage their own Pythons via mise.
# -----------------------------------------------------------------------------
RUN pip install --break-system-packages --no-cache-dir \
    jupyterlab \
    notebook \
    ipywidgets \
 && ln -sf $(python3 -c "import sysconfig; print(sysconfig.get_path('scripts'))")/jupyter /usr/local/bin/jupyter

# -----------------------------------------------------------------------------
# Kubeflow: expose port and set entrypoint
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
