# Ubuntu-only stuff. Abort if not Ubuntu.
is_chromeos || return 1

apt_keys=()
apt_source_files=()
apt_source_texts=()
apt_packages=()
deb_installed=()
deb_sources=()

installers_path="$DOTFILES/caches/installers"

# Ubuntu distro release name, eg. "xenial"
release_name=$(lsb_release -c | awk '{print $2}')

function add_ppa() {
  apt_source_texts+=($1)
  IFS=':/' eval 'local parts=($1)'
  apt_source_files+=("${parts[1]}-debian-${parts[2]}-$release_name")
}

#############################
# WHAT DO WE NEED TO INSTALL?
#############################

# Misc.
apt_packages+=(
  build-essential
  cmatrix
  curl
  docker-ce
  docker-compose
  git-core
  groff
  htop
  id3tool
  jq
  nmap
  python-pip
  silversearcher-ag
  sl
  telnet
  thefuck
  tree
)

apt_packages+=(vim)

# https://github.com/neovim/neovim/wiki/Installing-Neovim
add_ppa ppa:neovim-ppa/stable
apt_packages+=(neovim)

# https://github.com/rvm/ubuntu_rvm
add_ppa ppa:rael-gc/rvm
apt_packages+=(rvm)

# https://github.com/rbenv/ruby-build/wiki
apt_packages+=(
  autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev
  libncurses5-dev libffi-dev libgdbm3 libgdbm-dev zlib1g-dev vim
)


if is_chromeos; then

  apt_keys+=(https://download.docker.com/linux/debian/gpg)
  apt_source_files+=(docker)
  apt_source_texts+=("deb https://download.docker.com/linux/debian stretch stable")
  apt_packages+=(docker-ce)

  # https://code.visualstudio.com/docs/setup/linux
  curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
  sudo install -o root -g root -m 644 -microfto.gpg /etc/apt/trusted.gpg.d/
  sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
  sudo apt-get update
  sudo apt-get -y install code
  #apt_keys+=(https://packages.microsoft.com/keys/microsoft.asc)
  #apt_source_files+=(vscode)
  #api_source_texts+=("deb https://packages.microsoft.com/repos/vscode stable main")
  #apt_packages+=(code)

  # https://www.charlesproxy.com/documentation/installation/apt-repository/
  apt_keys+=(https://www.charlesproxy.com/packages/apt/PublicKey)
  apt_source_files+=(charles)
  apt_source_texts+=("deb https://www.charlesproxy.com/packages/apt/ charles-proxy3 main")
  apt_packages+=(charles-proxy)

  # https://github.com/aluxian/Messenger-for-Desktop#linux
  # apt_keys+=('--keyserver pool.sks-keyservers.net --recv 6DDA23616E3FE905FFDA152AE61DA9241537994D')
  # apt_source_files+=(aluxian)
  # apt_source_texts+=("deb https://dl.bintray.com/aluxian/deb/ beta main")
  # apt_packages+=(messengerfordesktop)

  # Misc
  # https://github.com/mitchellh/vagrant/issues/7411
  deb_installed+=(/usr/bin/vagrant)
  deb_sources+=(https://releases.hashicorp.com/vagrant/1.9.2/vagrant_1.9.2_x86_64.deb)
  # https://github.com/vagrant-libvirt/vagrant-libvirt/issues/575
  # apt_packages+=(vagrant)
  # function postinstall_vagrant() {
  #   sudo sed -i'' "s/Specification.all = nil/Specification.reset/" /usr/lib/ruby/vendor_ruby/vagrant/bundler.rb
  # }

  # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=772598
  # apt_packages+=(steam)
  # function preinstall_steam() {
  #   echo steam steam/question select I AGREE | sudo debconf-set-selections
  #   echo steam steam/license note | sudo debconf-set-selections
  # }
fi

function other_stuff() {
  # Install Git Extras
  if [[ ! "$(type -P git-extras)" ]]; then
    e_header "Installing Git Extras"
    (
      cd $DOTFILES/vendor/git-extras &&
      sudo make install
    )
  fi
  # Install misc bins from zip file.
  install_from_zip ngrok 'https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip'
  install_from_zip terraform 'https://releases.hashicorp.com/terraform/0.9.2/terraform_0.9.2_linux_amd64.zip'
}

####################
# ACTUALLY DO THINGS
####################

# Add APT keys.
keys_cache=$DOTFILES/caches/init/apt_keys
IFS=$'\n' GLOBIGNORE='*' command eval 'setdiff_cur=($(<$keys_cache))'
setdiff_new=("${apt_keys[@]}"); setdiff; apt_keys=("${setdiff_out[@]}")
unset setdiff_new setdiff_cur setdiff_out

if (( ${#apt_keys[@]} > 0 )); then
  e_header "Adding APT keys (${#apt_keys[@]})"
  for key in "${apt_keys[@]}"; do
    e_arrow "$key"
    if [[ "$key" =~ -- ]]; then
      sudo apt-key adv $key
    else
      wget -qO- $key | sudo apt-key add -
    fi && \
    echo "$key" >> $keys_cache
  done
fi

# Add APT sources.
function __temp() { [[ ! -e /etc/apt/sources.list.d/$1.list ]]; }
source_i=($(array_filter_i apt_source_files __temp))

if (( ${#source_i[@]} > 0 )); then
  e_header "Adding APT sources (${#source_i[@]})"
  for i in "${source_i[@]}"; do
    source_file=${apt_source_files[i]}
    source_text=${apt_source_texts[i]}
    if [[ "$source_text" =~ ppa: ]]; then
      e_arrow "$source_text"
      sudo add-apt-repository -y $source_text
    else
      e_arrow "$source_file"
      sudo sh -c "echo '$source_text' > /etc/apt/sources.list.d/$source_file.list"
    fi
  done
fi

# Update APT.
e_header "Updating APT"
sudo apt-get -qq update

# Only do a dist-upgrade on initial install, otherwise do an upgrade.
e_header "Upgrading APT"
if is_dotfiles_bin; then
  sudo apt-get -qy upgrade
else
  sudo apt-get -qy dist-upgrade
fi

# Install APT packages.
installed_apt_packages="$(dpkg --get-selections | grep -v deinstall | awk 'BEGIN{FS="[\t:]"}{print $1}' | uniq)"
apt_packages=($(setdiff "${apt_packages[*]}" "$installed_apt_packages"))

if (( ${#apt_packages[@]} > 0 )); then
  e_header "Installing APT packages (${#apt_packages[@]})"
  for package in "${apt_packages[@]}"; do
    e_arrow "$package"
    [[ "$(type -t preinstall_$package)" == function ]] && preinstall_$package
    sudo apt-get -qq install "$package" && \
    [[ "$(type -t postinstall_$package)" == function ]] && postinstall_$package
  done
fi

# Install debs via dpkg
function __temp() { [[ ! -e "$1" ]]; }
deb_installed_i=($(array_filter_i deb_installed __temp))

if (( ${#deb_installed_i[@]} > 0 )); then
  mkdir -p "$installers_path"
  e_header "Installing debs (${#deb_installed_i[@]})"
  for i in "${deb_installed_i[@]}"; do
    e_arrow "${deb_installed[i]}"
    deb="${deb_sources[i]}"
    [[ "$(type -t "$deb")" == function ]] && deb="$($deb)"
    installer_file="$installers_path/$(echo "$deb" | sed 's#.*/##')"
    wget -O "$installer_file" "$deb"
    sudo dpkg -i "$installer_file"
  done
fi

# install bins from zip file
function install_from_zip() {
  local name=$1 url=$2 bins b zip tmp
  shift 2; bins=("$@"); [[ "${#bins[@]}" == 0 ]] && bins=($name)
  if [[ ! "$(which $name)" ]]; then
    mkdir -p "$installers_path"
    e_header "Installing $name"
    zip="$installers_path/$(echo "$url" | sed 's#.*/##')"
    wget -O "$zip" "$url"
    tmp=$(mktemp -d)
    unzip "$zip" -d "$tmp"
    for b in "${bins[@]}"; do
      sudo cp "$tmp/$b" "/usr/local/bin/$(basename $b)"
    done
    rm -rf $tmp
  fi
}

# Run anything else that may need to be run.
type -t other_stuff >/dev/null && other_stuff
