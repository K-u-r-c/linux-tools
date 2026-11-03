#!/usr/bin/env bash
# install.sh — instaluje i aktualizuje narzędzia z https://github.com/K-u-r-c/linux-tools
#
#   ./install.sh                         -> lista komponentów i stan
#   ./install.sh hypr waybar tmux        -> instaluje wybrane (klon z GitHuba)
#   ./install.sh all                     -> wszystko
#   ./install.sh --deps <komponenty|all> -> najpierw pakiety (pacman / paru|yay)
#   ./install.sh --update                -> git pull we wszystkich zainstalowanych
#
# Istniejący katalog, który nie jest klonem danego repo, trafia do <katalog>.bak-<data>.
set -euo pipefail

GH="https://github.com/K-u-r-c"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
APPS_DIR="${LINUX_TOOLS_APPS:-$HOME/.local/share}"   # programy (nie configi)
BIN_DIR="$HOME/.local/bin"
STAMP=$(date +%Y%m%d-%H%M%S)

ALL=(hypr waybar alacritty tmux nvim command-center wall-downloader)

target() {
    case "$1" in
        command-center|wall-downloader) echo "$APPS_DIR/$1" ;;
        *) echo "$CONFIG_DIR/$1" ;;
    esac
}

desc() {
    case "$1" in
        hypr)            echo "Hyprland: config, tapety (hyprpaper/mpvpaper), monitory, HDR, wygaszacz, numer pulpitu" ;;
        waybar)          echo "terminalowy pasek z auto-hide i ikonami okien na pulpitach" ;;
        alacritty)       echo "terminal: czarny, przezroczysty" ;;
        tmux)            echo "tmux bez paska – pokazuje się po Ctrl+Space" ;;
        nvim)            echo "Neovim (LazyVim) z LSP, DAP, Godot" ;;
        command-center)  echo "HUD pod SUPER+TAB: aplikacje, audio, jasność, BT, zrzuty, tapety" ;;
        wall-downloader) echo "pobieranie animowanych tapet z MoeWalls" ;;
    esac
}

# pakiety z repo / z AUR
deps() {
    case "$1" in
        hypr)            echo "hyprland hyprpaper jq wofi grim slurp wl-clipboard hypridle cmatrix python-gobject gtk3 gtk-layer-shell python-cairo" ;;
        waybar)          echo "waybar jq ttf-meslo-nerd playerctl pavucontrol" ;;
        alacritty)       echo "alacritty" ;;
        tmux)            echo "tmux" ;;
        nvim)            echo "neovim git gcc make unzip ripgrep fd lazygit gitui nodejs npm python ttf-meslo-nerd" ;;
        command-center)  echo "python-gobject gtk3 gtk-layer-shell libpulse bluez-utils ffmpeg wl-clipboard xdg-utils ddcutil pacman-contrib" ;;
        wall-downloader) echo "python-gobject gtk3 mpv ffmpeg" ;;
    esac
}
aur_deps() {
    case "$1" in
        hypr) echo "mpvpaper" ;;
    esac
}

# ~/.local/bin/<nazwa> -> plik w repo
links() {
    case "$1" in
        command-center)  echo "command-center:command_center.py command-center-restart:cc-restart.sh" ;;
        wall-downloader) echo "wall-downloader:wall_downloader.py" ;;
    esac
}

say() { printf '\033[1m:: %s\033[0m\n' "$*"; }

is_clone() { # is_clone <katalog> <nazwa>
    [[ -d "$1/.git" ]] && git -C "$1" remote get-url origin 2>/dev/null | grep -qiE "K-u-r-c/$2(\.git)?$"
}

install_deps() {
    local pkgs=() aur=()
    for c in "$@"; do read -ra p <<<"$(deps "$c")"; pkgs+=("${p[@]}"); read -ra a <<<"$(aur_deps "$c")"; aur+=("${a[@]}"); done
    say "Pakiety: ${pkgs[*]}"
    sudo pacman -S --needed "${pkgs[@]}"
    ((${#aur[@]})) || return 0
    local helper=""
    command -v yay >/dev/null && helper=yay
    command -v paru >/dev/null && helper=paru
    if [[ -n "$helper" ]]; then "$helper" -S --needed "${aur[@]}"
    else echo "!! Brak paru/yay – z AUR doinstaluj ręcznie: ${aur[*]}"; fi
}

post_install() {
    local c="$1" dir="$2"
    for l in $(links "$c"); do
        mkdir -p "$BIN_DIR"
        ln -sfn "$dir/${l#*:}" "$BIN_DIR/${l%%:*}"
        echo "   $BIN_DIR/${l%%:*} -> $dir/${l#*:}"
    done
    case "$c" in
        hypr)
            [[ -e "$dir/monitors.conf" ]] || { cp "$dir/monitors.default.conf" "$dir/monitors.conf"
                echo "   monitors.conf z szablonu (autodetekcja) – dopasuj: $dir/monitors-detect.sh"; } ;;
        tmux)
            if [[ -e "$HOME/.tmux.conf" ]]; then   # ma pierwszeństwo przed ~/.config/tmux/tmux.conf
                mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak-$STAMP"
                echo "   ~/.tmux.conf -> ~/.tmux.conf.bak-$STAMP"
            fi ;;
        nvim)
            if command -v nvim >/dev/null; then
                echo "   pluginy z lazy-lock.json (chwilę to trwa)…"
                nvim --headless "+Lazy! restore" +qa &>/dev/null || echo "!! odpal nvim i :Lazy restore"
            fi ;;
    esac
}

install_one() {
    local c="$1" dir
    dir=$(target "$c")
    say "$c -> $dir"
    if is_clone "$dir" "$c"; then
        git -C "$dir" pull --ff-only -q && echo "   już był – zaktualizowany"
    else
        if [[ -e "$dir" || -L "$dir" ]]; then
            mv "$dir" "$dir.bak-$STAMP"
            echo "   stary katalog -> $dir.bak-$STAMP"
        fi
        mkdir -p "$(dirname "$dir")"
        git clone -q "$GH/$c.git" "$dir"
    fi
    post_install "$c" "$dir"
}

update_all() {
    for c in "${ALL[@]}"; do
        local dir; dir=$(target "$c")
        is_clone "$dir" "$c" || continue
        if git -C "$dir" pull --ff-only -q; then echo "  [ok] $c ($(git -C "$dir" log -1 --format='%h %s'))"
        else echo "  [!!] $c – lokalne zmiany? sprawdź: git -C $dir status"; fi
    done
    # tylko demon z tej instalacji (ścieżka w cmdline), nie np. drugi command center z innego katalogu
    local cc_dir; cc_dir=$(target command-center)
    if pgrep -f "^python[0-9.]* ($BIN_DIR/command-center|$cc_dir/command_center\.py)( |\$)" >/dev/null &&
       [[ -x "$BIN_DIR/command-center-restart" ]]; then
        setsid -f "$BIN_DIR/command-center-restart" >/dev/null 2>&1 </dev/null
        echo "  command center zrestartowany"
    fi
}

status() {
    echo "Komponenty (./install.sh <nazwa…> | all):"
    for c in "${ALL[@]}"; do
        local dir mark=" "; dir=$(target "$c")
        is_clone "$dir" "$c" && mark="✓"
        printf '  [%s] %-16s %s\n' "$mark" "$c" "$(desc "$c")"
    done
}

with_deps=false
comps=()
for a in "$@"; do
    case "$a" in
        --update) update_all; exit 0 ;;
        --deps) with_deps=true ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        all) comps+=("${ALL[@]}") ;;
        *) [[ " ${ALL[*]} " == *" $a "* ]] || { echo "Nieznany komponent: $a"; status; exit 1; }
           comps+=("$a") ;;
    esac
done
((${#comps[@]})) || { status; exit 0; }

$with_deps && install_deps "${comps[@]}"
for c in "${comps[@]}"; do install_one "$c"; done
say "Gotowe"
[[ ":$PATH:" == *":$BIN_DIR:"* ]] || echo "Dodaj $BIN_DIR do PATH."
