#!/usr/bin/env bash
set -euo pipefail

# Set verbosity
shopt -s nocasematch
case ${LOG_LEVEL} in
  error)
    __verbosity="--verbosity 1"
    ;;
  warn)
    __verbosity="--verbosity 2"
    ;;
  info)
    __verbosity="--verbosity 3"
    ;;
  debug)
    __verbosity="--verbosity 4"
    ;;
  trace)
    __verbosity="--verbosity 5"
    ;;
  *)
    echo "LOG_LEVEL ${LOG_LEVEL} not recognized"
    __verbosity=""
    ;;
esac

__public_ip=$(curl -s ifconfig.me/ip)
__ancient=""

if [ -n "${ANCIENT_DIR}" ] && [ ! "${ANCIENT_DIR}" = ".nada" ]; then
  echo "Using separate ancient directory at ${ANCIENT_DIR}."
  __ancient="--datadir.ancient /var/lib/geth/ancient"
fi

if [ -f /var/lib/geth/data/prune-marker ]; then
  rm -f /var/lib/geth/data/prune-marker

  wget "$(curl -s https://api.github.com/repos/coredao-org/core-chain/releases/latest |grep browser_ |grep "${NETWORK}" |cut -d\" -f4)"
  unzip -o "${NETWORK}".zip
  mv ${NETWORK}/* .
  rm -rf ${NETWORK}
  rm "${NETWORK}".zip

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__ancient} snapshot prune-block --block-amount-reserved 1024
else
  if [ -n "${SNAPSHOT}" ] && [ ! -f /var/lib/geth/data/setupdone ]; then
    if [ -n "${__ancient}" ]; then
       __snap_dir=/var/lib/geth/ancient/snapshot
       __data_dir=/var/lib/geth/ancient
    else
       __snap_dir=/var/lib/geth/data/snapshot
       __data_dir=/var/lib/geth/data
    fi
    # Check for enough space

    __free_space=$(df -P "${__data_dir}" | awk '/[0-9]%/{print $(NF-2)}')
    if [ -z "$__free_space" ]; then
        echo "Unable to determine free disk space. This is a bug."
        echo "Aborting"
        exit 1
    fi
    __filesize=$(curl -Is "${SNAPSHOT}" | grep -i Content-Length | awk '{print $2}')
    __filesize=${__filesize%$'\r'}
    if [ -z "$__filesize" ]; then
        echo "Unable to determine SNAPSHOT size, downloading optimistically"
    elif (( __filesize * 2 + 1073741824 > __free_space * 1024 )); then
        __free_gib=$(( __free_space / 1024 / 1024 ))
        __file_gib=$(( __filesize / 1024 / 1024 / 1024 ))
        echo "SNAPSHOT is $__file_gib GiB and you have $__free_gib GiB free."
        echo "You need at least 2x the size of the snapshot plus a safety buffer of 10 GiB."
        echo "Continuing anyway, but that may fail."
    fi

    mkdir -p "${__snap_dir}"
    __dont_rm=0
    aria2c -c -s14 -x14 -k100M -d ${__snap_dir} --auto-file-renaming=false --conditional-get=true \
      --allow-overwrite=true "${SNAPSHOT}"
    echo "Copy completed, extracting"
    cd "${__snap_dir}"
    filename=$(echo "${SNAPSHOT}" | awk -F/ '{print $NF}')
    if [[ "${filename}" =~ \.tar\.zst$ ]]; then
      pzstd -c -d "${filename}" | tar xvf - -C ${__data_dir}
    elif [[ "${filename}" =~ \.tar\.gz$ || "${filename}" =~ \.tgz$ ]]; then
      tar xzvf "${filename}" -C ${__data_dir}
    elif [[ "${filename}" =~ \.tar$ ]]; then
      tar xvf "${filename}" -C ${__data_dir}
    elif [[ "${filename}" =~ \.lz4$ ]]; then
      lz4 -d "${filename}" | tar xvf - -C ${__data_dir}
    else
      __dont_rm=1
      echo "The snapshot file has a format that Core Docker can't handle."
      echo "Please come to CryptoManufaktur Discord to work through this."
      exit 1
    fi
    if [ "${__dont_rm}" -eq 0 ]; then
      rm -f "${filename}"
    fi

    if [[ ! -d "${__data_dir}/geth/chaindata" ]]; then
      echo "Chaindata isn't in the expected location."
      echo "This snapshot likely won't work until the entrypoint script has been adjusted for it."
      exit 1
    fi

    if [ -n "${__ancient}" ]; then
        rm -rf /var/lib/geth/data/geth
        mkdir -p /var/lib/geth/data/geth/chaindata
        find "/var/lib/geth/ancient/geth" -mindepth 1 -maxdepth 1 ! -name 'chaindata' -exec mv {} /var/lib/geth/data/geth/ \;
        find "/var/lib/geth/ancient/geth/chaindata" -mindepth 1 -maxdepth 1 ! -name 'ancient' -exec mv {} /var/lib/geth/data/geth/chaindata/ \;
        find "/var/lib/geth/ancient/geth/chaindata/ancient" -mindepth 1 -maxdepth 1 -exec mv {} "/var/lib/geth/ancient/" \;
        rm -rf "/var/lib/geth/ancient/geth"
    fi
    touch /var/lib/geth/data/setupdone
  fi

  cd /var/lib/geth

  # The wget was moved down here so that repeated failures with SNAPSHOT above don't exhaust
  # the github API rate limit
  wget "$(curl -s https://api.github.com/repos/coredao-org/core-chain/releases/latest |grep browser_ |grep "${NETWORK}" |cut -d\" -f4)"
  unzip -o "${NETWORK}".zip
  mv ${NETWORK}/* .
  rm -rf ${NETWORK}
  rm "${NETWORK}".zip

  # Remove unwanted settings in config.toml
  dasel delete -f config.toml Node.LogConfig
  dasel delete -f config.toml Node.HTTPHost
  dasel delete -f config.toml Node.HTTPVirtualHosts

  # Set user-supplied static nodes, and also as trusted nodes
  if [ -n "${EXTRA_STATIC_NODES}" ]; then
    for string in $(jq -r .[] <<< "${EXTRA_STATIC_NODES}"); do
# Word splitting is desired
# shellcheck disable=SC2086,SC2046,SC2116
      dasel put -v $(echo $string) -f config.toml 'Node.P2P.StaticNodes.[]'
# shellcheck disable=SC2086,SC2046,SC2116
      dasel put -v $(echo $string) -f config.toml 'Node.P2P.TrustedNodes.[]'
    done
  fi

  # Sync from genesis if no snapshot was downloaded, above
  if [ ! -d /var/lib/geth/data/geth/chaindata ]; then
    echo "No SNAPSHOT provided in .env."
    echo "Initiating sync from genesis."
  fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__ancient} --nat extip:${__public_ip} ${__verbosity} ${EXTRAS}
fi
