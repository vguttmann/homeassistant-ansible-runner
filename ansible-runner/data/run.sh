#!/usr/bin/with-contenv bashio
# vim: ft=bash
# shellcheck shell=bash

# shellcheck disable=SC2034
CONFIG_PATH=/data/options.json
HOME=~

REPOSITORY=$(bashio::config 'repository')
GIT_BRANCH=$(bashio::config 'git_branch')
GIT_REMOTE=$(bashio::config 'git_remote')
ANSIBLE_PLAYBOOK=$(bashio::config 'ansible_playbook')
ANSIBLE_VAULT_SECRET=$(bashio::config 'ansible_vault_secret')
GIT_COMMAND=$(bashio::config 'git_command')
GIT_PRUNE=$(bashio::config 'git_prune')
DEPLOYMENT_KEY=$(bashio::config 'deployment_key')
DEPLOYMENT_USER=$(bashio::config 'deployment_user')
DEPLOYMENT_PASSWORD=$(bashio::config 'deployment_password')
DEPLOYMENT_KEY_PROTOCOL=$(bashio::config 'deployment_key_protocol')
REPEAT_ACTIVE=$(bashio::config 'repeat.active')
REPEAT_INTERVAL=$(bashio::config 'repeat.interval')
################

#### functions ####
function add-ssh-key {
    bashio::log.info "[Info] Start adding SSH key"
    mkdir -p ~/.ssh

    (
        echo "Host *"
        echo "    StrictHostKeyChecking no"
    ) > ~/.ssh/config

    bashio::log.info "[Info] Setup deployment_key on id_${DEPLOYMENT_KEY_PROTOCOL}"
    rm -f "${HOME}/.ssh/id_${DEPLOYMENT_KEY_PROTOCOL}"
    while read -r line; do
        echo "$line" >> "${HOME}/.ssh/id_${DEPLOYMENT_KEY_PROTOCOL}"
    done <<< "$DEPLOYMENT_KEY"

    chmod 600 "${HOME}/.ssh/config"
    chmod 600 "${HOME}/.ssh/id_${DEPLOYMENT_KEY_PROTOCOL}"
}

function git-clone {
    # git clone
    bashio::log.info "[Info] Start git clone"
    git clone "$REPOSITORY" /data/ || bashio::exit.nok "[Error] Git clone failed"
}

function check-ssh-key {
if [ -n "$DEPLOYMENT_KEY" ]; then
    bashio::log.info "Check SSH connection"
    IFS=':' read -ra GIT_URL_PARTS <<< "$REPOSITORY"
    # shellcheck disable=SC2029
    DOMAIN="${GIT_URL_PARTS[0]}"
    if OUTPUT_CHECK=$(ssh -T -o "StrictHostKeyChecking=no" -o "BatchMode=yes" "$DOMAIN" 2>&1) || { [[ $DOMAIN = *"@github.com"* ]] && [[ $OUTPUT_CHECK = *"You've successfully authenticated"* ]]; }; then
        bashio::log.info "[Info] Valid SSH connection for $DOMAIN"
    else
        bashio::log.warning "[Warn] No valid SSH connection for $DOMAIN"
        add-ssh-key
    fi
fi
}

function setup-user-password {
if [ -n "$DEPLOYMENT_USER" ]; then
    cd /config || return
    bashio::log.info "[Info] setting up credential.helper for user: ${DEPLOYMENT_USER}"
    git config --system credential.helper 'store --file=/tmp/git-credentials'

    # Extract the hostname from repository
    h="$REPOSITORY"

    # Extract the protocol
    proto=${h%%://*}

    # Strip the protocol
    h="${h#*://}"

    # Strip username and password from URL
    h="${h#*:*@}"
    h="${h#*@}"

    # Strip the tail of the URL
    h=${h%%/*}

    # Format the input for git credential commands
    cred_data="\
protocol=${proto}
host=${h}
username=${DEPLOYMENT_USER}
password=${DEPLOYMENT_PASSWORD}
"

    # Use git commands to write the credentials to ~/.git-credentials
    bashio::log.info "[Info] Saving git credentials to /tmp/git-credentials"
    # shellcheck disable=SC2259
    git credential fill | git credential approve <<< "$cred_data"
fi
}

function git-synchronize {
    # is /config a local git repo?
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        bashio::log.warning "[Warn] Git repository doesn't exist"
        git-clone
        return
    fi

    bashio::log.info "[Info] Local git repository exists"
    # Is the local repo set to the correct origin?
    CURRENTGITREMOTEURL=$(git remote get-url --all "$GIT_REMOTE" | head -n 1)
    if [ "$CURRENTGITREMOTEURL" != "$REPOSITORY" ]; then
        bashio::exit.nok "[Error] git origin does not match $REPOSITORY!";
        return
    fi

    bashio::log.info "[Info] Git origin is correctly set to $REPOSITORY"
    OLD_COMMIT=$(git rev-parse HEAD)

    # Always do a fetch to update repos
    bashio::log.info "[Info] Start git fetch..."
    git fetch "$GIT_REMOTE" "$GIT_BRANCH" || bashio::exit.nok "[Error] Git fetch failed";

    # Prune if configured
    if [ "$GIT_PRUNE" == "true" ]
    then
        bashio::log.info "[Info] Start git prune..."
        git prune || bashio::exit.nok "[Error] Git prune failed";
    fi

    # Do we switch branches?
    GIT_CURRENT_BRANCH=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
    if [ -z "$GIT_BRANCH" ] || [ "$GIT_BRANCH" == "$GIT_CURRENT_BRANCH" ]; then
        bashio::log.info "[Info] Staying on currently checked out branch: $GIT_CURRENT_BRANCH..."
    else
        bashio::log.info "[Info] Switching branches - start git checkout of branch $GIT_BRANCH..."
        git checkout "$GIT_BRANCH" || bashio::exit.nok "[Error] Git checkout failed"
        GIT_CURRENT_BRANCH=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
    fi

    # Pull or reset depending on user preference
    case "$GIT_COMMAND" in
        pull)
            bashio::log.info "[Info] Start git pull..."
            git pull || bashio::exit.nok "[Error] Git pull failed";
            ;;
        reset)
            bashio::log.info "[Info] Start git reset..."
            git reset --hard "$GIT_REMOTE"/"$GIT_CURRENT_BRANCH" || bashio::exit.nok "[Error] Git reset failed";
            ;;
        *)
            bashio::exit.nok "[Error] Git command is not set correctly. Should be either 'reset' or 'pull'"
            ;;
    esac
}

function ansible-dry-run {
    STRIPPED_PATH="${ANSIBLE_PLAYBOOK#/}"
    PLAYBOOK_NAME="${STRIPPED_PATH##*/}"
    DIRNAME="${STRIPPED_PATH%/*}"
    if [[ -z "$DIRNAME" ]]; then
       bashio::exit.nok "[Error] Ansible Playbook not present. Should be something like 'folder/subfolder/playbook.yaml'"
    fi
    if [[ -n "$DIRNAME" ]]; then
       cd $DIRNAME
    fi

    set -o pipefail

    ansible-playbook $PLAYBOOK_NAME --vault-password-file ~/.vault_pass.txt 2>&1 | while read -r LINE; do
        bashio::log.info "$LINE"
    done
    return ${PIPESTATUS[0]}

}

###################

#### Main program ####
while true; do
    bashio::log.info "[Info] Starting runner..."
    check-ssh-key
    setup-user-password
    git-synchronize
    pwd
    ls -la
    ls -la
    # ansible-dry-run
    #  # do we repeat?
    # if [ ! "$REPEAT_ACTIVE" == "true" ]; then
    #     exit 0
    # fi
    # sleep "$REPEAT_INTERVAL"
done

###################