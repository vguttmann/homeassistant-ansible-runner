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
PLAYBOOK_PATH="${ANSIBLE_PLAYBOOK#/}"
PLAYBOOK_PATH="${PLAYBOOK_PATH%/*}"
PLAYBOOK_NAME="${ANSIBLE_PLAYBOOK#/}"
PLAYBOOK_NAME="${PLAYBOOK_NAME##*/}"
IFS='/' read -ra GIT_URL_PARTS <<< "$REPOSITORY"
REPO_NAME=${GIT_URL_PARTS[-1]%.git}
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
    cd /tmp/repo
    git clone "$REPOSITORY" || bashio::exit.nok "[Error] Git clone failed"
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
    cd /tmp/repo/${REPO_NAME} || return
    bashio::log.info "[Info] setting up credential.helper for user: ${DEPLOYMENT_USER}"
    git config credential.helper 'store --file=/tmp/git-credentials'

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
    cd /tmp/
    cd /
    bashio::log.info "[Info] Checking if /tmp/repo exists"
    if [ ! -d /tmp/repo ]; then
        bashio::log.info "[Info] /tmp/repo does not exist, creating it"
        mkdir /tmp/repo
    fi
    cd /tmp/
    ls -Rla | while read -r LINE; do
        bashio::log.info "[Info] $LINE"
    done

    cd /tmp/repo
    # @TODO: Handle other repos existing alongside
    if [ ! -d "$REPO_NAME" ]; then
        bashio::log.warning "[Warn] Git repository doesn't exist"
        rm -rf /tmp/repo/
        git-clone
    fi

    bashio::log.info "[Info] Local git repository exists"
    # Is the local repo set to the correct origin?
    cd $REPO_NAME
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

function setup-ansible-vault-creds {
    bashio::log.info "[Info] Attempting to set up Ansible Vault creds"
}

function ansible-run {

    if [[ -z "$ANSIBLE_PLAYBOOK" ]]; then
       bashio::exit.nok "[Error] Ansible Playbook not specified. Should be something like 'folder/subfolder/playbook.yaml'"
    fi
    cd $PLAYBOOK_PATH
    bashio::log.info "[Info] Performing dry run..."
    ansible all -m ping 2>&1 | while read -r LINE; do
        bashio::log.info "[Info] $LINE"
    done
    ansible-dry-run
    if [ $? -eq 2 ]; then
        bashio::log.info "[Info] Changes will be made. Performing wet run now.."
        ansible-wet-run
        if [ $? -eq 2 ]; then
            bashio::log.info "[Info] Ansible wet run completed with changes"
        elif [ $? -eq 0]; then
            bashio::exit.nok "[Error] Ansible wet run finished with error."
        elif [ $? -eq 0]; then
            bashio::exit.error "[Error] Ansible wet run finished without changes. This should not be possible"
        else
            bashio::exit.nok "[Error] Ansible dry run finished with an exit code other than 0, 1, or 2. Either this hasn't been updated in forever, or something has gone even more horribly wrong"
        fi
    elif [ $? -eq 1]; then
        bashio::exit.nok "[Error] Ansible dry run finished with errors. Not attempting wet run"
    elif [ $? -eq 0]; then
        bashio::log.info "[Info] Ansible dry run finished without changes. Not attempting wet run"
    else
        bashio::exit.nok "[Error] Ansible dry run finished with an exit code other than 0, 1, or 2. Either this hasn't been updated in forever, or something has gone horribly wrong"
    fi

}

function ansible-dry-run {
    ansible-playbook $PLAYBOOK_NAME --check --diff --vault-password-file ~/.vault_pass.txt 2>&1 | while read -r LINE; do
        bashio::log.info "[Info] $LINE"
    done
    return ${PIPESTATUS[0]}
}

function ansible-wet-run {
    ansible-playbook $PLAYBOOK_NAME --check --diff --vault-password-file ~/.vault_pass.txt 2>&1 | while read -r LINE; do
    bashio::log.info "[Info] $LINE"
    done
    return ${PIPESTATUS[0]}

}

###################

#### Main program ####
while true; do
    bashio::log.info "[Info] Starting runner..."
    check-ssh-key
    setup-user-password
    setup-ansible-vault-creds
    git-synchronize
    ansible-run
     # do we repeat?
    if [ ! "$REPEAT_ACTIVE" == "true" ]; then
        exit 0
    fi
    sleep "$REPEAT_INTERVAL"
done

###################