#!/bin/bash

# todo: list
# todo: save passphrase? not recommended

#export 'PS4=+${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}():'

gpg_bin="$(command -v gpg)"
openssl_bin="$(command -v openssl)"
[[ -z "${gpg_bin}${openssl_bin}" ]] && {
    printf 'Install either GPG or OpenSSL to use pass...\n'
    return 1
}

password_file=~/.pass/passwords
password_conf=~/.pass/pass.conf

[[ -d $(dirname ${password_file}) ]] || mkdir ${password_file}
[[ -f ${password_file} ]] || touch ${password_file}
[[ -f ${password_conf} ]] || touch ${password_conf}
chmod 600 ${password_file} ${password_conf}

pass()
{
    action='none'
    for arg in "$@"; do
        case "${arg}" in
            g|get|r|read) action='get'; break ;;
            u|update) action='update'; break ;;
            c|config) action='configure'; break ;;
            d|delete) action='delete'; break ;;
        esac
    done

    [[ "${action}" = 'none' ]] && {
        usage
        return 1
    }

    declare passphrase
    declare resource
    declare account

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

                passphrase="$(get_passphrase)"
                echo

                declare index=3
                [[ "${searchfor}" = *,* ]] || (( --index ))

                set -o pipefail
                decrypt "${passphrase}" | grep "^${searchfor}," | cut -d, -f${index}- | sed 's/^,//; s/,/: /' || \
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
                key="${resource},${account}"
                key="${key##,}"
                [[ -z "${key}" ]] && {
                    usage
                    return 1
                }

                outfile=$(mktemp)
                passphrase="$(get_passphrase)"
                echo

                read -rp '>> password? ' password
                decrypt "${passphrase}" "${password_file}" | grep -v "^${key}," > "${outfile}"
                echo "${key},${password}" >> "${outfile}"
                encrypt "${passphrase}" "${outfile}" && \
                    printf 'Added R:%s, A:%s\n' "${resource:-(none)}" "${account}"
                ;;
            x|debug) set -x ;;
            d|delete)
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

                decrypt "${passphrase}" "${password_file}" | grep -v "^${searchfor}," > ${outfile}
                encrypt "${passphrase}" "${outfile}" && \
                    printf 'Deleted R:%s, A:%s\n' "${searchfor%,*}" "${account:-(all)}"
                ;;
            c|config)
                shift
                case "${1}" in
                    get-*)
                        declare key="${1#*-}"
                        grep -q "^${key} = " ${password_conf} 2>/dev/null || {
                            printf '%s not configured. Use "pass config set-%s <value>" to set.\n' "${key^}" "${key}"
                            return 0
                        }
                        printf '%s %s\n' "${key^}" "$(awk -F' = ' "/^${key}/ {print \$NF}" ${password_conf})"
                        ;;
                    set-*)
                        declare key=${1#*-} value="${2}"
                        [[ -z "${value}" ]] && {
                            printf 'Missing value for set-%s\n' "${key}"
                            return 1
                        }
                        { [[ "${key}" = 'encryption' ]] && [[ -s ${password_file} ]]; } && {
                            printf 'Cannot change encryption (password file: %d bytes)\n' "$(stat -c %s ${password_file})"
                            return 1
                        }
                        sed -i "/^${key}/d" ${password_conf}
                        echo "${key} = ${value}" >> ${password_conf}
                        printf 'Set %s to "%s"\n' "${key}" "${value}"
                        shift
                        ;;
                esac
                ;;
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
    printf 'pass config get-<key>\n'
    printf '\tgets the current value of <key> from the config file\n'
    printf 'pass config set-<key> <value>\n'
    printf '\tadds <key> = <value> to the config\n'
    # todo
    printf '\n'
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
    echo $$ >> /tmp/pass.lock
    flock -${type:-s} -w 3 ${fd}
}

release_lock()
{
    [[ "${1}" -eq 1 ]] && echo
    grep -q $$ /tmp/pass.lock && {
        declare -i fd=7
        flock -u ${fd}
        sed -i "/$$/d" /tmp/pass.lock
    }
}

decrypt()
{
    method="$(get_encryption)" || {
        printf "%s\n" "${method}"
        return 1
    }
    if acquire_lock 'read'; then
        declare passphrase="${1}"
        case "${method}" in
            gpg) echo "${passphrase}" | ${gpg_bin} --yes --batch --passphrase-fd 0 --decrypt ${password_file} 2>/dev/null ;;
            openssl) ${openssl_bin} enc -d -aes-256-cbc -md sha512 -pbkdf2 -in ${password_file} -k "${passphrase}" ;;
        esac
        release_lock
    fi
}

encrypt()
{
    method="$(get_encryption)" || {
        printf "%s\n" "${method}"
        return 1
    }
    if acquire_lock 'write'; then
        declare passphrase="${1}"
        declare plaintext="${2}"
        case "${method}" in
            gpg) { echo "${passphrase}"; echo "${passphrase}"; } | ${gpg_bin} --yes --batch --passphrase-fd 0 --symmetric --output ${password_file} "${plaintext}" ;;
            openssl) ${openssl_bin} enc -aes-256-cbc -md sha512 -pbkdf2 -in "${plaintext}" -k "${passphrase}" -out ${password_file} ;;
        esac
        release_lock
    fi
}

get_passphrase()
{
    declare passphrase
    read -srp '>> passphrase? ' passphrase
    echo "${passphrase}"
}

get_encryption()
{
    method="$(awk -F' = ' '/^encryption = / {print $NF}' ${password_conf})"
    [[ -z "${method}" ]] && {
        printf 'Encryption method not configured! Please set with "pass config set-encryption <method>".\n'
        return 1
    }
    echo "${method}"
}

trap 'release_lock 1' EXIT
