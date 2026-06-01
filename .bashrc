#
# ~/.bashrc
#
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
        source /etc/profile.d/vte.sh
fi

eval "$(oh-my-posh init bash --config $HOME/.config/ohmyposh/themes/blue-owl.omp.json)"


ssh-posh() {
    # 1. Wyciągamy czysty adres IP lub domenę z parametrów SSH
    local TARGET_HOST=$(echo "$@" | awk -F'@' '{print $NF}' | awk '{print $1}')
    
    # 2. Bezbłędne wyciąganie portu z parametrów pętlą (szukamy -p lub -P)
    local TARGET_PORT="22"
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "-p" || "${args[i]}" == "-P" ]]; then
            TARGET_PORT="${args[i+1]}"
            break
        fi
    done

    # 3. Tworzymy unikalny plik gniazda dla duetu IP + PORT
    local CONTROL_SOCKET="/tmp/ssh-share-${TARGET_HOST}-${TARGET_PORT}"

    # 4. Czyszczenie starego gniazda na wypadek, gdyby wisiało w pamięci RAM
    /usr/bin/ssh -O exit -S "$CONTROL_SOCKET" 2>/dev/null
    
    # 5. Sprawdzamy system operacyjny przez unikalny tunel kontrolny (hasło tylko raz)
    local IS_UNIX=$(
	umask 0077	
	/usr/bin/ssh -o ControlMaster=auto -o ControlPath="$CONTROL_SOCKET" -o ControlPersist=0m -o ConnectTimeout=0 "$@" "uname" 2>/dev/null)

    # 6. WARUNEK: Jeśli zdalna usługa to system Unix (Linux lub macOS)
    if [ -n "$IS_UNIX" ]; then

        # Generujemy oryginalny, niebieski prompt
        local LOCAL_PROMPT=$(oh-my-posh print primary --config /home/akeri0n/.config/ohmyposh/themes/blue-owl.omp.json --shell bash)

        # POPRAWKA 1: Zamiana nazwy hosta na \h wraz z jej domeną systemową (usuwamy domeny tutaj)
        LOCAL_PROMPT=$(echo "$LOCAL_PROMPT" | sed 's|amdbox\.akeri0n\.systems|\\h|g; s|amdbox|\\h|g')

        # POPRAWKA 2: Dokładna zamiana nazwy użytkownika tylko tam, gdzie występuje samodzielnie
        LOCAL_PROMPT=$(echo "$LOCAL_PROMPT" | sed 's|\bakeri0n\b|\\u|g; s|akeri0n|\\u|g')

        # POPRAWKA 3: Czyszczenie ewentualnych pozostałych ogonów domenowych maszyn zdalnych
        LOCAL_PROMPT=$(echo "$LOCAL_PROMPT" | sed 's|\.systems||g; s|\.nomachine||g; s|\.local||g')



        # 3. DYNAMICZNA ŚCIEŻKA (Uniwersalna):
        # Pobieramy nazwę bieżącego katalogu lokalnego (np. Documents)
        local LOCAL_DIR="${PWD##*/}"
        
        # Jeśli jesteśmy w katalogu domowym, LOCAL_DIR będzie puste lub będzie nazwą użytkownika.
        # Wtedy Oh-My-Posh używa ikony domku (\ueb06). Obsługujemy oba przypadki:
        if [ "$PWD" = "$HOME" ]; then
            LOCAL_PROMPT=$(echo "$LOCAL_PROMPT" | sed $'s/\ueb06/REMOTE:\\\\W/g')
        elif [ -n "$LOCAL_DIR" ]; then
            LOCAL_PROMPT=$(echo "$LOCAL_PROMPT" | sed "s|$LOCAL_DIR|REMOTE:\\\W|g")
        fi

        # NOWOŚĆ: Jeśli hostem docelowym jest macOS (Darwin), używamy formatowania printf %s.
        # To całkowicie uodparnia skrypt na zniekształcenia cudzysłowów i znaki specjalne na Macu.
        if [ "$IS_UNIX" = "Darwin" ]; then
            /usr/bin/ssh -o ControlPath="$CONTROL_SOCKET" -t "$@" "
            export BASH_SILENCE_DEPRECATION_WARNING=1
                exec bash --rcfile <(printf '%s' '[ -f /etc/bash.bashrc ] && source /etc/bash.bashrc; [ -f ~/.bashrc ] && source ~/.bashrc; export PS1=\"$LOCAL_PROMPT\"')
            "
        else
            # ŚCIEŻKA DLA LINUKSA (Twój oryginalny, nienaruszony kod z obsługą sudo su):
            /usr/bin/ssh -o ControlPath="$CONTROL_SOCKET" -t "$@" "
                exec bash --rcfile <(echo '
                    [ -f /etc/bash.bashrc ] && source /etc/bash.bashrc
                    [ -f ~/.bashrc ] && source ~/.bashrc
                    
                    export PS1=\"$LOCAL_PROMPT\"
                    echo \"export PS1=\\\"$LOCAL_PROMPT\\\"\" > ~/.bash_ssh_prompt

                    sudo() {
                        if [ \"\$1\" = \"su\" ]; then
                            /usr/bin/sudo bash --rcfile ~/.bash_ssh_prompt
                        else
                            /usr/bin/sudo \"\$@\"
                        fi
                    }
                    
                    trap \"rm -f ~/.bash_ssh_prompt\" EXIT
                ')
            "
        fi
    else
        # 7. ŚCIEŻKA DLA WINDOWS (CMD / PowerShell - Twój oryginalny kod):
        /usr/bin/ssh -o ControlPath="$CONTROL_SOCKET" "$@"
    fi

    # 8. Po zakończeniu sesji bezwzględnie likwidujemy to konkretne gniazdo
    /usr/bin/ssh -O exit -S "$CONTROL_SOCKET" 2>/dev/null 
#    rm -f "$CONTROL_SOCKET"
#    return 0
    # Czekamy ułamek sekundy na zwolnienie blokady przez proces SSH przed usunięciem pliku
    local RETRIES=0
    while [ -S "$CONTROL_SOCKET" ] && [ $RETRIES -lt 5 ]; do
        rm -f "$CONTROL_SOCKET" 2>/dev/null
        sleep 0.1
        ((RETRIES++))
    done

    return 0

}
alias ssh="ssh-posh"

