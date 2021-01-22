#!/usr/bin/env bash

set -Eeuo pipefail
trap _cleanup SIGINT SIGTERM ERR EXIT

BLACK=$(tput -Txterm setaf 0)
RED=$(tput -Txterm setaf 1)
GREEN=$(tput -Txterm setaf 2)
YELLOW=$(tput -Txterm setaf 3)
BLUE=$(tput -Txterm setaf 4)
MAGENTA=$(tput -Txterm setaf 5)
CYAN=$(tput -Txterm setaf 6)
WHITE=$(tput -Txterm setaf 7)
RESET=$(tput -Txterm sgr0)

export SERVER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

source "$SERVER_DIR/core/_main.sh"

_usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") ${MAGENTA}[OPTIONS]${RESET} ${BLUE}COMMAND${RESET}

${CYAN}This script aims to manage a home server based on Docker, Docker Compose, Make and Bash.${RESET}

${WHITE}Available options:${RESET}
  ${YELLOW}-h, --help      ${GREEN}Print this help and exit${RESET}

${WHITE}Available commands:${RESET}
  ${YELLOW}install         ${GREEN}Install all services${RESET}
  ${YELLOW}uninstall       ${GREEN}Uninstall all services${RESET}
  ${YELLOW}start           ${GREEN}Start all services${RESET}
  ${YELLOW}stop            ${GREEN}Stop all services${RESET}
  ${YELLOW}restart         ${GREEN}Restart all services${RESET}
  ${YELLOW}status          ${GREEN}Get the status of all services${RESET}
  ${YELLOW}services        ${GREEN}Open a menu based on FZF to manage the services separately${RESET}

EOF
  exit
}

_cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}

_parse_params() {
  allowed_commands=(install uninstall start stop restart status services)

  while :; do
    case "${1-}" in
    -h | --help) _usage ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  [[ ${#args[@]} -eq 0 ]] && die "Missing script command"
  [[ ! " ${allowed_commands[@]} " =~ " ${args[0]} " ]] && die "Unknown script command '${args[0]}'"

  return 0
}

_check_requirements() {
  DOCKER_EXE=$(/usr/bin/which docker || echo 0)
  checks::executable_check ${DOCKER_EXE} "docker"
  DOCKER_VERSION=$(${DOCKER_EXE} --version | cut -f 3 -d' ' | cut -f 1,2 -d '.');
  checks::version_check ${DOCKER_VERSION} ${MINIMUM_DOCKER_VERSION} "Docker"

  DOCKER_COMPOSE_EXE=$(/usr/bin/which docker-compose || echo 0)
  checks::executable_check ${DOCKER_COMPOSE_EXE} "docker-compose"
  DOCKER_COMPOSE_VERSION="$(${DOCKER_COMPOSE_EXE} --version | cut -f 3 -d' ' | cut -f 1,2 -d '.')";
  checks::version_check ${DOCKER_COMPOSE_VERSION} ${MINIMUM_DOCKER_COMPOSE_VERSION} "Docker Compose"

  MAKE_EXE=$(/usr/bin/which make || echo 0)
  checks::executable_check ${MAKE_EXE} "make"
  MAKE_EXE_VERSION="$(${MAKE_EXE} --version | head -n 1 | cut -f 3 -d' ' | cut -f 1,2 -d '.')";
  checks::version_check ${MAKE_EXE_VERSION} ${MINIMUM_MAKE_VERSION} "Make"
}

_install() {
  _check_requirements
  docker network create traefik-network
  for service in "${SERVICES[@]}"
  do
    make -s -C "$SERVER_DIR/services/$service" install
  done
}

_uninstall() {
  for service in "${SERVICES[@]}"
  do
    make -s -C "$SERVER_DIR/services/$service" uninstall
  done
  docker network rm traefik-network
}

_start() {
  for service in "${SERVICES[@]}"
  do
    make -s -C "$SERVER_DIR/services/$service" up
  done
}

_stop() {
  for service in "${SERVICES[@]}"
  do
    make -s -C "$SERVER_DIR/services/$service" down
  done
}

_restart() {
  for service in "${SERVICES[@]}"
  do
    make -C "$SERVER_DIR/services/$service" restart
  done
}

_status() {
  for service in "${SERVICES[@]}"
  do
    service_status=$(make -s -C "$SERVER_DIR/services/$service" health)
    if [ "$service_status" == "UP" ]; then
      log::success "$service is UP"
    else
      log::error "$service is DOWN"
    fi
  done
}

_services() {
  for service in "${SERVICES[@]}"
    do
      if [ ! -f "$SERVER_DIR/services/$service/.disabled" ]; then
        services_string+="$(make -pRrq -C "$SERVER_DIR/services/$service" : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($1 !~ "^[#.]") {print $1}}' | sort | egrep -v -e '^[^[:alnum:]]' | awk -v service_prefix="${service} " '{ print service_prefix $0}' || true)\n"
      else
        services_string+="$service enable\n"
      fi
    done
  target=($(echo -e "$services_string" | awk 'NF' | xargs -I % sh -c 'echo %' | fzf --height 50% \
            --preview 'make -s -C "$SERVER_DIR/services/"$(echo {} | cut -d" " -f 1) help'))
  log::note "Executing 'make ${target[1]}' for service '${target[0]}'"
  make -s -C "$SERVER_DIR/services/${target[0]}" ${target[1]}
}

## Global variables ##
SERVICES=($(ls $SERVER_DIR/services))
MINIMUM_DOCKER_VERSION=19.03
MINIMUM_DOCKER_COMPOSE_VERSION=1.25
MINIMUM_MAKE_VERSION=4.2

## Logic ##
_parse_params "$@"

case "${args[0]-}" in
  install) _install ;;
  uninstall) _uninstall ;;
  start) _start ;;
  stop) _stop ;;
  restart) _restart ;;
  status) _status ;;
  services) _services ;;
  -?*) die "Unknown option: $1" ;;
  *) echo "none" ;;
esac
