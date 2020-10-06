#!/bin/bash

todo()
{
    case ${1} in
        add)
            shift
            d="$(date +"%F %T")"
            [[ -r ~/.todo ]] || touch ~/.todo
            lines=$(wc -l ~/.todo | awk '{print $1}')
            printf "%d: %s $*\n" "$(( lines + 1 ))" "${d}" >> ~/.todo
            printf "TODO: Added \"$*\" [%s]\n" "${d}"
            ;;

        mark)
            shift
            if grep -v "^COMPLETED" ~/.todo | grep "$*"; then
                read -rp "Mark these notes completed? [Y/N] " response
                case ${response,,} in
                    yes|y)
                        sed -i "/^[0-9].*$*/s/^\(.*\)/COMPLETED \1 $(date +%s)/" ~/.todo
                        ;;
                esac
            fi
            ;;

        list)
            shift
            printf '\nTODO list:\n'
            pattern="${1}"
            [ -n "${pattern}" ] || pattern=___
            shift
            case "${pattern}" in
                all)
                    grep --color=never "${*:-.*}" ~/.todo
                    ;;
                ___)
                    grep -v "^COMPLETED " ~/.todo | grep --color=never "${1:-.*}"
                    ;;
                *)
                    grep --color=never "${pattern}" ~/.todo
                    ;;
            esac
            LAST_TODO_LIST=$(date +%s)
            export LAST_TODO_LIST
            ;;

        *)
            printf 'Usage: todo [add|mark|list]\n'
            printf '    add \tadds a todo\n'
            printf '    mark\tmarks a todo done\n'
            printf '    list\tlists incomplete todos\n'
            return 0
            ;;

    esac
}
