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
    HOME="/home/${NB_USER}" \
    SHELL="/bin/zsh"

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
    python3-pip \
    python3-venv \
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

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable \
 && . /usr/local/cargo/env \
 && rustup default stable \
 && cargo install eza \
 && cargo install du-dust \
 && cargo install dysk \
 && cargo install xh \
 && cargo install ripgrep \
 && cargo install lesser \
 && cargo install bat \
 && rm -rf /usr/local/cargo/registry /usr/local/cargo/git

# -----------------------------------------------------------------------------
# btop — install prebuilt binary from GitHub releases (not in Ubuntu 24.04 apt)
# -----------------------------------------------------------------------------
RUN curl -fsSL "https://github.com/aristocratos/btop/releases/download/v1.4.7/btop-x86_64-unknown-linux-musl.tar.gz" -o /tmp/btop.tar.gz \
 && tar -xzf /tmp/btop.tar.gz -C /tmp \
 && cp /tmp/btop/bin/btop /usr/local/bin/btop \
 && chmod +x /usr/local/bin/btop \
 && rm -rf /tmp/btop /tmp/btop.tar.gz

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
# Shared zsh config snippet — applied to both jovyan and root
# -----------------------------------------------------------------------------
RUN cat > /etc/zsh/zshenv << 'ZSHENV'
export MISE_DATA_DIR="/usr/local/mise"
export MISE_CONFIG_DIR="/usr/local/mise"
export MISE_CACHE_DIR="/usr/local/mise/cache"
export PATH="/usr/local/cargo/bin:/usr/local/mise/shims:/usr/local/bin:$PATH"
export SHELL=/bin/zsh
ZSHENV

# Shared aliases and config written to /etc/zsh/zshrc.local
RUN cat > /etc/zsh/zshrc.local << 'ZSHRC'
# oh-my-zsh (sourced per-user below)
export ZSH_THEME="minimal"
alias ls="eza --icons"
alias l="eza -xa --icons --group-directories-first"
alias ll="eza -lTa --icons --group-directories-first --level=1"
alias lll="eza -lTa --icons --group-directories-first --level=2"
alias top="btop"
alias less="bat"
eval "$(mise activate zsh)"
cd /projects
ZSHRC

# -----------------------------------------------------------------------------
# oh-my-zsh for jovyan
# -----------------------------------------------------------------------------
RUN su - ${NB_USER} -c \
    'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' \
 && sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="minimal"/' /home/${NB_USER}/.zshrc \
 && echo 'source /etc/zsh/zshrc.local' >> /home/${NB_USER}/.zshrc \
 && echo 'exec /bin/zsh -i' > /home/${NB_USER}/.bashrc

# -----------------------------------------------------------------------------
# oh-my-zsh for root
# -----------------------------------------------------------------------------
RUN HOME=/root ZSH=/root/.oh-my-zsh sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
 && sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="minimal"/' /root/.zshrc \
 && echo 'source /etc/zsh/zshrc.local' >> /root/.zshrc \
 && echo 'exec /bin/zsh -i' > /root/.bashrc

# Tell JupyterLab terminals to use zsh
# Use /etc/jupyter (system-wide, never overwritten by PVC mounts)
# Also write to /etc/environment so SHELL is available to all processes
RUN mkdir -p /etc/jupyter \
 && printf 'c.ServerApp.terminado_settings = {"shell_command": ["/bin/zsh", "-i"]}\nc.ServerApp.root_dir = "/projects"\n' > /etc/jupyter/jupyter_server_config.py \
 && echo 'SHELL=/bin/zsh' >> /etc/environment

# -----------------------------------------------------------------------------
# Install JupyterLab via pip (system Python from base image) so the notebook
# server can start. Users manage their own Pythons via mise.
# -----------------------------------------------------------------------------
RUN python3 -m pip install --break-system-packages --no-cache-dir \
    jupyterlab \
    notebook \
    ipywidgets

# -----------------------------------------------------------------------------
# Node.js 26 via mise (needed for Claude Code and Codex)
# Then install Claude Code and OpenAI Codex globally
# -----------------------------------------------------------------------------
RUN mise install node@26 \
 && mise use --global node@26 \
 && mise reshim \
 && npm install -g @anthropic-ai/claude-code \
 && npm install -g @openai/codex


# -----------------------------------------------------------------------------
# Kubeflow: expose port and set entrypoint
# -----------------------------------------------------------------------------
USER ${NB_USER}
WORKDIR /projects
EXPOSE 8888

ENTRYPOINT ["tini", "--"]
CMD ["/bin/zsh", "-i", "-c", \
     "/usr/local/bin/jupyter lab \
       --ip=0.0.0.0 \
       --port=8888 \
       --no-browser \
       --allow-root \
       --ServerApp.token='' \
       --ServerApp.password='' \
       --ServerApp.allow_origin='*' \
       --ServerApp.base_url=${NB_PREFIX} \
       --ServerApp.root_dir=/projects \
       --ServerApp.terminado_settings='{\"shell_command\": [\"/bin/zsh\"]}' "]
