#!/bin/bash

# todo: list
# todo: what should the behavior be if just passing a resource?
#       right now get() prints all passwords for the resource
# todo: use openssl if gpg isn't available (default to openssl?)
# todo: save passphrase? not recommended

#export 'PS4=+${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}():'

gpg_bin="$(command -v gpg)"
[[ -z "${gpg_bin}" ]] && {
    printf 'Installing GPG...\n'
    apt-get install gpg
}

password_file=~/.pass/passwords
[[ -d $(dirname ${password_file}) ]] || mkdir ~/.pass
[[ -f ${password_file} ]] || touch ${password_file}
chmod 600 ${password_file}

pass()
{
    action='none'
    for arg in "$@"; do
        case "${arg}" in
            g|get|r|read) action='get'; break ;;
            u|update) action='update'; break ;;
        esac
    done

    [[ "${action}" = 'none' ]] && {
        usage
        return 1
    }

    declare resource
    declare account

    declare passphrase
    read -srp '>> passphrase? ' passphrase
    echo

    while (( $# )); do
        case "${1//-}" in
            g|get|r|retrieve)
                shift
                [[ -z "${1}" ]] || account="${1}"
                [[ -z "${2}" ]] || {
                    shift
                    resource="${account}"
                    account="${1}"
                }
                declare searchfor
                [[ -z "${resource}" ]] || searchfor="${resource},"
                searchfor="${searchfor}${account}"
                [[ -z "${searchfor}" ]] && {
                    usage
                    return 1
                }
                set -o pipefail
                decrypt "${passphrase}" | grep "^${searchfor}," | cut -d, -f3- | sed 's/^,//' || \
                    printf 'Password not found! (R:%s, A:%s)\n' "${resource:-(none)}" "${account}"
                set +o pipefail
                ;;
            u|update)
                shift
                [[ -z "${1}" ]] || account="${1}"
                [[ -z "${2}" ]] || {
                    shift
                    resource="${account}"
                    account="${1}"
                }
                declare outfile key password
                key="${resource},${account},"
                key="${key##,}"
                [[ -z "${key//,}" ]] && {
                    usage
                    return 1
                }
                outfile=$(mktemp)
                read -rp '>> password? ' password
                decrypt "${passphrase}" "${password_file}" | grep -v "^${key}" > ${outfile}
                echo "${key},${password}" >> ${outfile}
                encrypt "${passphrase}" "${outfile}"
                ;;
            d|debug) set -x ;;
            *)
                usage
                return 1
                ;;
        esac
        shift
    done
    set +x
}

usage()
{
    printf 'Usage: pass <action> ...\n\n'
    printf 'Ex.\n'
    printf 'pass get network home-15\n'
    printf '\tgets the password for network resource, home-15 account ("retrieve" is a synonym)\n'
    printf 'pass update internet apple "password123"\n'
    printf '\tadd the password "password123" to the internet resource, apple account\n\n'
    printf 'g, r, and u are synonyms for get, retrieve, and update, respectively\n'
}

acquire_lock()
{
    declare -i fd=7
    declare type
    case "${1}" in
        r|read)  type='s' ;;
        w|write) type='x' ;;
    esac

    eval "exec ${fd}>/tmp/pass.lock"
    flock -${type:-s} -w 3 ${fd}
}

release_lock()
{
    [[ "${1}" -eq 1 ]] && echo
    declare -i fd=7
    flock -u ${fd}
}

decrypt()
{
    if acquire_lock 'read'; then
        declare passphrase="${1}"
        echo "${passphrase}" | ${gpg_bin} --yes --batch --passphrase-fd 0 --decrypt ${password_file} 2>/dev/null
        release_lock
    fi
}

encrypt()
{
    if acquire_lock 'write'; then
        declare passphrase="${1}"
        declare plaintext="${2}"
        { echo "${passphrase}"; echo "${passphrase}"; } | ${gpg_bin} --yes --batch --passphrase-fd 0 --symmetric --output ${password_file} ${plaintext}
        release_lock
    fi
}

trap 'release_lock 1' EXIT
