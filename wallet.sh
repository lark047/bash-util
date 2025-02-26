#!/bin/bash

wallet()
{
    declare wdir=~/.wallet
    [[ -d ${wdir} ]] || mkdir ${wdir}
    [[ -r ${wdir}/index ]] || touch ${wdir}/index
    case "${1//-}" in
        a|add)
            shift
            declare id name number expires cvv wfile
            read -rp 'Name on card: ' name
            read -rp 'Number: ' number
            read -rp 'Expiration Date (YYYY-DD-MM): ' expires
            read -rp 'CVV: ' cvv
            [[ -z "${1}" ]]  || id="${1}"
            [[ -z "${id}" ]] && id="${number##*-}"
            # todo: decrypt index
            grep -q "${id}" ${wdir}/index && {
                printf 'Refusing to overwrite existing entry\n' >&2
                return 1
            }
            wfile="$(mktemp -p ${wdir} secret.XXXXXXX)"
            echo "${id},${wfile##*/}" >> ${wdir}/index
            # todo: encrypt index
            echo "{
    \"id\": \"${id}\",
    \"name\": \"${name}\",
    \"number\": \"${number}\",
    \"expires\": \"${expires}T00:00:00.000$(date +%:z)\",
    \"cvv\": ${cvv}
}" > ${wfile}
            printf 'Added "%s"\n' "${id}"
            # todo: encrypt file
            ;;
        h|help)   ;;
        l|list)
            shift
            printf 'Secrets in this wallet:\n'
            while IFS=, read -r id secret; do
                fn=${wdir}/${secret}
                #printf '\t%s\tc: %s\t u:%s\n' "${id}" "$(stat -c %w ${fn})" "$(stat -c %y ${fn})"
                printf '\t%s\n' "${id}"
            done < ${wdir}/index
            ;;
        s|show)
            shift
            [[ -z "${1}" ]] && {
                printf 'Show what?\n' >&2
                return 1
            }
            declare id="${1}" secret exp
            secret="$(awk -F',' "/^${id},/ {print \$NF}" ${wdir}/index)"
            [[ -z "${secret}" ]] && {
                printf '"%s" not found\n' "${id}" >&2
                return 1
            }
            exp="$(date -d "$(jq -r '.expires' ${wdir}/${secret})" +"%m/%y")"
            printf '+------------------------+\n'
            printf '| (logo)                 |\n'
            printf '|                        |\n'
            printf '| %-20s   |\n' "$(jq -r '.name'  ${wdir}/${secret})"
            printf '| %-20s   |\n' "$(jq -r '.number'  ${wdir}/${secret})"
            printf '| Exp: %s   CVV: %-4s |\n' "${exp}" "$(jq -r '.cvv' ${wdir}/${secret})"
            printf '+------------------------+\n'
            ;;
        u|update) ;;
        # *) set -- 'h'; wallet ;;
    esac
}
