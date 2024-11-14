# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

cat .bashrc >> ~/.bashrc

cp .tmux.conf ~/.tmux.conf

# Install basic utils
sudo apt update
sudo apt-get -y install git curl tmux vim neovim wget python3 python3-dev python3-venv

# Vim plug Install
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# Set neovim config
mkdir -p ~/.config/nvim
cp neovim_init.vim ~/.config/nvim/init.vim
# Set base python environment
cd ~
python3 -m venv .venv
~/.venv/bin/python -m pip install -U pip pynvim ruff numpy opencv-python pillow typing_extensions

# Install plugs
nvim --headless +PlugInstall +qall

printf "\n${GREEN}source ~/.bashrc${NC} for updating bash commands\n"

