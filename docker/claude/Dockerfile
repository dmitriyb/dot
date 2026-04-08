FROM fedora:latest

# Install core tools from Fedora repos
RUN dnf install -y \
    fish tmux neovim btop git eza fzf bat zoxide direnv \
    ffmpeg ImageMagick stow git-lfs openssh-clients \
    nodejs npm curl \
    procps-ng \
    && dnf clean all

# Install starship (not in Fedora repos)
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y

# Install lazygit (not in Fedora repos)
RUN dnf copr enable -y atim/lazygit && dnf install -y lazygit && dnf clean all

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Install TPM (tmux plugin manager)
RUN git clone https://github.com/tmux-plugins/tpm /usr/share/tmux-plugin-manager

# Create non-root user
RUN useradd -m -s /usr/bin/fish dev

USER dev
WORKDIR /home/dev

# Clone and stow dotfiles
RUN git clone https://github.com/dmitriyb/dot.git /home/dev/dot \
    && mkdir -p /home/dev/.config \
    && cd /home/dev/dot \
    && stow -t /home/dev/.config config \
    && stow -t /home/dev bin

# Set theme
RUN /home/dev/.local/bin/theme-set gruvbox

# Skip onboarding, set vim mode and theme
RUN echo '{"hasCompletedOnboarding":true,"theme":"dark-ansi","editorMode":"vim","numStartups":1}' > /home/dev/.claude.json

# Install tmux plugins
RUN /usr/share/tmux-plugin-manager/bin/install_plugins

WORKDIR /workspace

ENTRYPOINT ["fish"]
