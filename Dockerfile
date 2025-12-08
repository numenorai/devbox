# Start from a slim but common base
FROM debian:bookworm-slim

# Prevents some interactive prompts during install
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    nano \
    xz-utils \
    build-essential \
    pkg-config \
    libssl-dev \
    cmake \
    ninja-build \
    ncurses-dev \
    libedit-dev \
    libgmp-dev \
    zlib1g-dev \
    libarchive-dev \
    libossp-uuid-dev \
    libdb-dev \
    libpcre2-dev \
    libyaml-dev \
    python3 \
    libpython3-dev \
    unixodbc-dev \
    fzf \
    btop \
    htop \
    sqlite3 \
    libsqlite3-dev \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# Install uv (Astral's Python tool / package manager)
# See: https://docs.astral.sh/uv/ for the latest installer snippet
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Put uv on PATH (the installer typically puts it under ~/.local/bin)
ENV PATH="/root/.local/bin:${PATH}"

# Use uv to install Python 3.13
# This gives you a managed Python toolchain without system python
RUN uv python install 3.13

# Create a shim so that `python` runs uv-managed Python 3.13
RUN ln -s "$(uv python find 3.13)" /usr/local/bin/python

# Install Playwright (Python, via uv) plus system deps and browsers
RUN uv tool install playwright && \
    playwright install-deps && \
    playwright install

# Install Node.js (latest from NodeSource, multi-arch)
RUN curl -fsSL https://deb.nodesource.com/setup_current.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code (global CLI)
RUN npm install -g @anthropic-ai/claude-code

# Install GitHub CLI (multi-arch via official GitHub apt repo)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Build and install SWI-Prolog from source (latest stable V9.2.4)
ARG SWIPL_VERSION=V9.2.4

RUN git clone --branch ${SWIPL_VERSION} https://github.com/SWI-Prolog/swipl.git /tmp/swipl && \
    cd /tmp/swipl && \
    git submodule update --init --recursive && \
    mkdir build && cd build && \
    cmake -G Ninja .. && \
    ninja -j"$(nproc)" && \
    ninja install && \
    rm -rf /tmp/swipl

# Install Rust using rustup (portable for amd64 + arm64)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && \
    echo 'source $HOME/.cargo/env' >> /root/.bashrc

# Install bat (Rust-based cat replacement)
RUN . "$HOME/.cargo/env" && cargo install bat --locked

# Install useful Rust-based command-line utilities
RUN . "$HOME/.cargo/env" && \
    \
    # zoxide — smarter cd command that remembers directory usage
    cargo install zoxide --locked && \
    \
    # ripgrep (rg) — extremely fast recursive search tool
    cargo install ripgrep --locked && \
    \
    # fselect — SQL-like CLI for finding files
    cargo install fselect --locked && \
    \
    # rusty-man — view Rust documentation in the terminal
    cargo install rusty-man --locked && \
    \
    # delta — syntax-highlighting pager for git/diff
    cargo install git-delta --locked && \
    \
    # tokei — counts lines of code in a directory
    cargo install tokei --locked && \
    \
    # mprocs — modern TUI for running multiple commands in parallel
    cargo install mprocs --locked && \
    \
    # gitui — fast and user-friendly TUI for Git repositories
    cargo install gitui --locked

# ---------- Helix editor install (multi-arch) ----------

# Helix version to install – bump this if you want a newer release
ARG HELIX_VERSION=25.07.1

# TARGETARCH is provided by Docker/BuildKit (amd64, arm64, etc.)
ARG TARGETARCH

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) HELIX_ARCH="x86_64" ;; \
      arm64) HELIX_ARCH="aarch64" ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -L "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-${HELIX_ARCH}-linux.tar.xz" \
      -o /tmp/helix.tar.xz; \
    mkdir -p /opt/helix; \
    tar -xJf /tmp/helix.tar.xz -C /opt/helix --strip-components=1; \
    ln -s /opt/helix/hx /usr/local/bin/hx; \
    rm /tmp/helix.tar.xz

# Helix default configuration for all containers
RUN mkdir -p /root/.config/helix && \
    cat << 'EOF' > /root/.config/helix/config.toml
theme = "ao"
EOF

# Add Prolog language support for Helix
RUN mkdir -p /root/.config/helix && \
    cat << 'EOF' > /root/.config/helix/languages.toml
[[language]]
name = "prolog"
scope = "source.prolog"
roots = []
file-types = ["pl", "pro"]
comment-token = "%"
indent = { tab-width = 4, unit = "    " }
EOF

RUN apt-get update && \
    apt-get install -y --no-install-recommends bc qalc && \
    rm -rf /var/lib/apt/lists/*

# ---------- Runtime layout ----------

# Set a working directory for your code
WORKDIR /app

# Custom minimal prompt: HH:MM in yellow + path in cyan + ❯
RUN echo 'export PS1="\[\033[33m\]\A \[\033[36m\]\w\[\033[0m\] ❯ "' >> /root/.bashrc

# Optional: copy project into image (you’ve left this off for now)
# COPY . /app

# Declare a volume for persistent data
VOLUME ["/data"]

ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV TZ=Pacific/Honolulu
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8
ENV LC_ALL=C.UTF-8

# Useful shell aliases
RUN echo 'alias l="ls --color"' >> /root/.bashrc && \
    echo 'alias ll="ls -al --color"' >> /root/.bashrc && \
    echo 'alias ..="cd .."' >> /root/.bashrc && \
    echo 'alias c="clear"' >> /root/.bashrc && \
    echo 'alias gl="git pull"' >> /root/.bashrc && \
    echo 'alias gs="git status"' >> /root/.bashrc && \
    echo 'alias gp="git push"' >> /root/.bashrc && \
    echo 'alias gc="git commit -m"' >> /root/.bashrc && \
    echo 'alias ga="git add"' >> /root/.bashrc

ENV PATH="/root/.cargo/bin:${PATH}"

# ---------- GNU Prolog (gprolog) from source ----------
ARG GPROLOG_VERSION=1.5.0

RUN set -eux; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        m4 \
        texinfo && \
    cd /tmp && \
    wget "https://downloads.sourceforge.net/project/gprolog/${GPROLOG_VERSION}/gprolog-${GPROLOG_VERSION}.tar.gz" && \
    tar -xzf "gprolog-${GPROLOG_VERSION}.tar.gz" && \
    cd "gprolog-${GPROLOG_VERSION}/src" && \
    ./configure && \
    make -j"$(nproc)" && \
    make install && \
    cd / && \
    rm -rf "/tmp/gprolog-${GPROLOG_VERSION}" "/tmp/gprolog-${GPROLOG_VERSION}.tar.gz" && \
    apt-get purge -y wget m4 texinfo && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# All persistent state lives under /data (volume)
ENV DEVBOX_DATA=/data \
    XDG_CONFIG_HOME=/data/config \
    XDG_CACHE_HOME=/data/cache \
    XDG_DATA_HOME=/data/share \
    CARGO_HOME=/data/cargo \
    GH_CONFIG_DIR=/data/gh \
    NPM_CONFIG_PREFIX=/data/npm-global \
    PLAYWRIGHT_BROWSERS_PATH=/data/playwright-browsers

ENV PATH="/root/.cargo/bin:/data/npm-global/bin:${PATH}"

# Default command when a container is run
CMD ["bash"]
