{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Editors and IDEs
    (vscode-with-extensions.override {
      vscode = vscodium;
      vscodeExtensions = [
        vscode-extensions.hashicorp.terraform
        vscode-extensions.jnoortheen.nix-ide
      ];
    }) # VSCodium with Terraform and Nix extensions
    helix # Modal terminal text editor
    neovim # Extensible modal text editor used by LazyVim
    nerd-fonts.jetbrains-mono # Patched icon font used by LazyVim
    zed-editor # Fast graphical code editor

    # Language servers and code formatters
    cue # CUE configuration language, formatter, and language server
    jsonnet-language-server # Language server for Jsonnet
    nixd # Language server for Nix
    nixfmt # Official formatter for Nix expressions
    package-version-server # Dependency-version hints for package manifests in Zed
    ruff # Python linter, formatter, and language server
    shfmt # Formatter for shell scripts
    stylua # Formatter for Lua
    tree-sitter # Parser framework used for syntax analysis
    vscode-json-languageserver # JSON validation, completion, and schema support
    rlsp-yaml # Fast schema-aware YAML language server

    # Programming languages and development environments
    asdf-vm # Manages multiple versions of language runtimes and tools
    bun # Incredibly fast JavaScript runtime, bundler, transpiler and package manager – all in one
    devbox # Creates reproducible per-project development environments
    gcc # C and C++ compiler toolchain
    nodejs_latest # JavaScript runtime and npm package manager
    python3 # Python interpreter
    uv # Fast Python package and virtual-environment manager

    # Source control and code navigation
    acli # Atlassian CLI for Jira, Confluence, and Bitbucket Cloud
    confluence-cli # Confluence CLI for self-hosted Data Center instances (pchuri/confluence-cli)
    jira-cli-go # Jira CLI for Cloud and Data Center instances (ankitpokhrel/jira-cli)
    fd # Fast alternative to find
    fzf # Interactive fuzzy finder
    git-graph # Terminal interface for browsing Git history
    glab # GitLab CLI
    ripgrep # Fast recursive text search

    # Containers and virtualization
    distrobox # Runs integrated Linux environments inside containers
    docker # Docker container client and tools
    podman # Daemonless container engine
    podman-tui # Terminal interface for Podman
    bubblewrap

    # Kubernetes, OpenStack, and infrastructure
    k9s # Terminal interface for Kubernetes clusters
    kubectl # Kubernetes command-line client
    krew # kubectl plugin manager
    kubectl-cnpg # CloudNativePG plugin for kubectl
    kubelogin-oidc # OIDC authentication plugin for kubectl
    openstackclient-full # Command-line client for OpenStack services
    s3cmd

    # Data formats, networking, and security tools
    bruno # Graphical API client and request collection manager
    dig # DNS query and troubleshooting utility
    dnslookup # Simple DNS lookup utility
    jq # JSON query and transformation tool
    mtr # Combined traceroute and network latency monitor
    nmap # Network scanner and service discovery tool
    openssl # TLS, certificates, and cryptographic utilities
    yq-go # YAML, JSON, and XML query and transformation tool
    ipcalc # Internet protocol calculator

    # Terminal and general CLI utilities
    atuin # Searchable shell history backed by SQLite
    bat # Syntax-highlighted alternative to cat
    bottom # Interactive terminal system monitor
    brightnessctl # Controls display and keyboard backlight brightness
    go-task # Task runner / simpler Make alternative written in Go
    htop # Interactive process and resource monitor
    pwgen # Generates random passwords
    silicon # Renders source code as styled images
    tree # Displays directory contents as a tree
    unzip # Extracts ZIP archives
    p7zip # Archive utility
    woeusb-ng # Windows bootable drive creation tool
    rar # Archive utility
    w3m # Text-mode web browser
    wget # Downloads files over HTTP, HTTPS, and FTP
    zip # Creates and modifies ZIP archives
    zellij # Terminal multiplexer and workspace manager
    ferrite # Terminal workspace and file-management utility

    # Wayland and desktop integration
    bemoji # Emoji picker for the desktop
    showmethekey # Displays pressed keys on screen
    ueberzugpp # Renders images inside supported terminals
    wl-clipboard # Wayland clipboard command-line tools
    wtype # Simulates keyboard input on Wayland

    # File managers, disks, and filesystems
    gparted # Graphical disk partition editor
    nautilus # GNOME graphical file manager
    ntfs3g # Read/write support for NTFS filesystems
    yazi # Terminal file manager

    # Documents, notes, and productivity
    anki # Spaced-repetition flashcard application
    deluge # Torrent tracker
    pinta # Drawing app
    drawing # Drawing app
    gimp # Drawing app
    krita # Drawing app
    doxx # Lightweight viewer for DOCX documents
    foliate # E-book reader
    libreoffice-qt # Office suite with Qt integration
    obsidian # Markdown-based notes and knowledge-base application
    ocrmypdf # Adds a searchable OCR text layer to scanned PDF files
    poppler-utils # PDF text, metadata and image extraction tools
    super-productivity # Task manager and time tracker
    (tesseract.override {
      enableLanguages = [
        "eng"
        "rus"
      ];
    }) # OCR engine with English and Russian recognition data

    # Audio, video, and graphics
    ffmpeg # Converts and processes audio and video
    ffmpegthumbnailer # Generates video thumbnails for file managers
    imv # Minimal image viewer
    mediainfo # Displays technical metadata for media files
    vlc # Media player and Streaming server
    mpv # Video and audio player
    obs-studio # Screen recording and live-streaming application
    yt-dlp # Downloads video and audio from supported websites

    # Music
    musicpod # Music, podcast, and internet-radio player
    nocturne # Graphical music player
    puddletag # Audio tag editor
    tauon # Desktop music player and library manager

    # Communication
    #discord
    legcord # Lightweight Discord client
    thunderbird # Email, calendar, and contacts client
    vencord # Discord client modification and plugin platform
    vesktop # Desktop Discord client with Vencord integration
    telegram-desktop # Telegram desktop client

    # Remote access
    freerdp # Command-line Remote Desktop Protocol client
    remmina # Graphical remote desktop client

    # Web and entertainment
    google-chrome # Web browser
    steam # PC game store, launcher, and compatibility platform

    # System and hardware utilities
    bluez # Linux Bluetooth protocol stack and utilities
    bluez-tools # Additional Bluetooth command-line utilities
    keepassxc # Offline password manager
    pavucontrol # Graphical PulseAudio and PipeWire volume control

    # Nix maintenance
    nix-prefetch-scripts # Calculates source hashes for Nix packages
  ];
}
