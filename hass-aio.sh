#!/bin/bash

AIO_VERSION="17.3.29"

echo "Home Assistant Installer v${AIO_VERSION}"
echo "Copyright(c) 2017 Dale Higgs <@dale3h>"
echo

if [[ $UID != 0 ]]; then
  echo "Please run this script with sudo:"
  echo "  sudo $0 $*"
  exit 1
fi

# General settings
IP_ADDRESS="$(ifconfig | awk -F':' '/inet addr/&&!/127.0.0.1/{split($2,_," ");print _[1]}')"
SERVICE_PATH="/etc/systemd/system"
ASSETS_URL="https://raw.githubusercontent.com/dale3h/hass-aio/master/assets"

# Virtualenv settings
VIRTUAL_ENV="/srv/homeassistant"
PIP_EXEC="$VIRTUAL_ENV/bin/pip3"
HASS_EXEC="$VIRTUAL_ENV/bin/hass"

# Home Assistant settings
HASS_CONFIG="/etc/homeassistant"
HASS_USER="homeassistant"
HASS_GROUP="$HASS_USER"
HASS_SERVICE="$SERVICE_PATH/home-assistant.service"
HASS_SERVICE_URL="$ASSETS_URL/home-assistant.service"

# Mosquitto settings
GPG_KEY_URL="http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key"
APT_LIST_URL="http://repo.mosquitto.org/debian/mosquitto-jessie.list"

MOSQUITTO_PATH="/etc/mosquitto"
MOSQUITTO_USER="mosquitto"
MOSQUITTO_GROUP="mosquitto"
MOSQUITTO_CONF="$MOSQUITTO_PATH/mosquitto.conf"
MOSQUITTO_CONF_URL="$ASSETS_URL/mosquitto.conf"
MOSQUITTO_PASSWD="$MOSQUITTO_PATH/passwd"
MOSQUITTO_SERVICE="$SERVICE_PATH/mosquitto.service"
MOSQUITTO_SERVICE_URL="$ASSETS_URL/mosquitto.service"

MQTT_USERNAME="homeassistant"
MQTT_PASSWORD="$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 12; echo)"

# Open Z-Wave settings
LIBMICROHTTPD_PATH="$VIRTUAL_ENV/src/libmicrohttpd"
LIBMICROHTTPD_URL="ftp://ftp.gnu.org/gnu/libmicrohttpd/libmicrohttpd-0.9.19.tar.gz"

# Log functions
ok() {
  echo -e "[\033[1;32m  OK  \033[0m] $@"
}

info() {
  echo -e "[\033[1;36m INFO \033[0m] $@"
}

fail() {
  echo -e "[\033[1;31m FAIL \033[0m] $@"
}

report() {
  local rc=$?
  [[ $rc == 0 ]] && ok "$@" || fail "$@"
  return $rc
}

# Installer functions
update_upgrade() {
  apt-get update && apt-get upgrade -y
  log "Update system packages"
}

install_deps() {
  apt-get install -y python3 python3-dev python3-pip curl git make swig
  log "Install apt-get dependencies"

  pip3 install --upgrade pip
  log "Upgrade python3-pip"

  pip3 install --upgrade virtualenv
  log "Install virtualenv"
}

install_users() {
  useradd -rmU "$HASS_USER"
  log "Create user '$HASS_USER'"

  usermod -aG dialout "$HASS_USER"
  log "Add user '$HASS_USER' to group 'dialout'"

  usermod -aG gpio "$HASS_USER"
  log "Add user '$HASS_USER' to group 'gpio'"

  usermod -aG video "$HASS_USER"
  log "Add user '$HASS_USER' to group 'video'"
}

install_dirs() {
  mkdir -p "$VIRTUAL_ENV"
  log "Create virtualenv directory: $VIRTUAL_ENV"

  chown -R $HASS_USER:$HASS_GROUP "$VIRTUAL_ENV"
  log "Change owner to '$HASS_USER': $VIRTUAL_ENV"

  mkdir -p "$HASS_CONFIG"
  log "Create configuration directory: $HASS_CONFIG"

  chown -R $HASS_USER:$HASS_GROUP "$HASS_CONFIG"
  log "Change owner to '$HASS_USER': $HASS_CONFIG"
}

install_venv() {
  virtualenv -p python3 "$VIRTUAL_ENV"
  log "Create virtual environment: $VIRTUAL_ENV"

  chown -R $HASS_USER:$HASS_GROUP "$VIRTUAL_ENV"
  log "Change owner to '$HASS_USER': $VIRTUAL_ENV"
}

install_mosquitto() {
  wget -qO - "$GPG_KEY_URL" | apt-key add -
  log "Add mosquitto GPG key"

  wget -qO /etc/apt/sources.list.d/mosquitto.list "$APT_LIST_URL"
  log "Add mosquitto repo"

  apt-get update && apt-get install -y mosquitto mosquitto-clients
  log "Install mosquitto"

  systemctl stop mosquitto
  log "Stop mosquitto service"

  systemctl disable mosquitto
  log "Disable mosquitto service"

  mv "$MOSQUITTO_CONF" "$MOSQUITTO_CONF.backup"
  log "Backup original mosquitto config"

  wget -qO "$MOSQUITTO_CONF" "$MOSQUITTO_CONF_URL"
  log "Install default mosquitto config"

  chown $MOSQUITTO_USER:$MOSQUITTO_GROUP "$MOSQUITTO_CONF"
  log "Change owner to '$MOSQUITTO_USER': $MOSQUITTO_CONF"

  touch "$MOSQUITTO_PASSWD"
  log "Initialize mosquitto password file"

  chown $MOSQUITTO_USER:$MOSQUITTO_GROUP "$MOSQUITTO_PASSWD"
  log "Change owner to '$MOSQUITTO_USER': $MOSQUITTO_PASSWD"

  chmod 0600 "$MOSQUITTO_PASSWD"
  log "Restrict access: $MOSQUITTO_PASSWD"

  mosquitto_passwd -b "$MOSQUITTO_PASSWD" "$MQTT_USERNAME" "$MQTT_PASSWORD"
  log "Create default MQTT username/password: $MQTT_USERNAME / $MQTT_PASSWORD"
}

install_homeassistant() {
  $PIP_EXEC install --upgrade homeassistant
  log "Install Home Assistant"

  chown -R $HASS_USER:$HASS_GROUP "$HASS_CONFIG"
  log "Change owner to '$HASS_USER': $HASS_CONFIG"
}

# install_permissions() {
#   # @todo Implement this
# }

install_services() {
  wget -qO "$HASS_SERVICE" "$HASS_SERVICE_URL"
  log "Install Home Assistant service"

  wget -qO "$MOSQUITTO_SERVICE" "$MOSQUITTO_SERVICE_URL"
  log "Install mosquitto service"

  systemctl daemon-reload
  log "Reload systemd services"

  systemctl enable $(basename "$HASS_SERVICE")
  log "Enable Home Assistant service"

  systemctl enable $(basename "$MOSQUITTO_SERVICE")
  log "Enable mosquitto service"
}

install_config() {
  $HASS_EXEC --script ensure_config --config "$HASS_CONFIG"
  log "Initialize configuration.yaml"

  echo <<EOF
mqtt:
  broker: !secret mqtt_broker
  port: !secret mqtt_port
  username: !secret mqtt_username
  password: !secret mqtt_password
EOF >> "$HASS_CONFIG/configuration.yaml"
  log "Add MQTT to configuration.yaml"

  chown -R $HASS_USER:$HASS_GROUP "$HASS_CONFIG"
  log "Change owner to '$HASS_USER': $HASS_CONFIG"
}

install_secrets() {
  touch "$HASS_CONFIG/secrets.yaml"
  log "Initialize secrets.yaml"

  echo <<EOF
mqtt_broker: '127.0.0.1'
mqtt_port: 1883
mqtt_username: '${MQTT_USERNAME}'
mqtt_password: '${MQTT_PASSWORD}'
EOF >> "$HASS_CONFIG/secrets.yaml"
  log "Add MQTT to secrets.yaml"

  chown -R $HASS_USER:$HASS_GROUP "$HASS_CONFIG"
  log "Change owner to '$HASS_USER': $HASS_CONFIG"
}

install_openzwave() {
  $PIP_EXEC install python_openzwave
  log "Install python-openzwave"

  chown -R $HASS_USER:$HASS_GROUP "$VIRTUAL_ENV"
  log "Change owner to '$HASS_USER': $VIRTUAL_ENV"
}

start_services() {
  systemctl restart $(basename "$HASS_SERVICE")
  log "Restart Home Assistant service"

  systemctl restart $(basename "$MOSQUITTO_SERVICE")
  log "Restart mosquitto service"
}

install_libmicrohttpd() {
  mkdir -p "$VIRTUAL_ENV/src"
  log "Create src directory: $VIRTUAL_ENV/src"

  pushd "$VIRTUAL_ENV/src"
  log "Change working directory: $(pwd)"

  wget -qO "$LIBMICROHTTPD_PATH.tar.gz" "$LIBMICROHTTPD_URL"
  log "Download libmicrohttpd"

  tar zxvf "$LIBMICROHTTPD_PATH.tar.gz"
  log "Extract libmicrohttpd"

  pushd "$LIBMICROHTTPD_PATH"
  log "Change working directory: $(pwd)"

  ./configure
  log "Configure libmicrohttpd"

  make
  log "Make libmicrohttpd"

  make install
  log "Install libmicrohttpd"

  popd
  log "Change working directory: $(pwd)"

  popd
  log "Change working directory: $(pwd)"

  chown -R $HASS_USER:$HASS_GROUP "$VIRTUAL_ENV"
  log "Change owner to '$HASS_USER': $VIRTUAL_ENV"
}

update_upgrade
log "Update and upgrade system packages"

install_deps
log "Install all dependencies"

install_users
log "Setup users"

install_dirs
log "Setup directories"

install_venv
log "Setup virtualenv"

install_mosquitto
log "Install mosquitto"

install_homeassistant
log "Install Home Assistant"

# install_permissions
# log "Setup permissions"

install_services
log "Install services"

install_config
log "Install Home Assistant configuration.yaml"

install_secrets
log "Install Home Assistant secrets.yaml"

install_openzwave
log "Install Open Z-Wave"

start_services
log "Start services"

echo
echo "Done!"
echo
echo "If you have issues with this script, please contact @dale3h on gitter.im"
