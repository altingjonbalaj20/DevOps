#! /bin/bash

BOX_SIZE="8 100"
MENU_BOX_OPTIONS="25 78 16 --cancel-button Exit"
SECRET_VALUE_BOX_SIZE="50 100"

SECRETS_DIR=~/.secrets
TEMP_DIR=$SECRETS_DIR/temp
BACKUP_DIR=$SECRETS_DIR/backup
SAVED_SECRETS_DIR=~/Documents/SAVED_SECRETS

CREDENTIALS_FILE=$SECRETS_DIR/credentials

init() {
    cd ~

    mkdir -p $SECRETS_DIR
    touch $CREDENTIALS_FILE

    mkdir -p $TEMP_DIR
    mkdir -p $BACKUP_DIR
    mkdir -p $SAVED_SECRETS_DIR
}

errorOccurred() {
    echo "To be implemented"
}

operationCanceled() {
    whiptail --title "Operation Canceled" --msgbox "Operation canceled, exiting..." $BOX_SIZE
    echo "Exiting..."
    exit 1
}

provideAccessKeyId() {
    AWS_ACCESS_KEY_ID=$(whiptail --inputbox "Provide AWS Access Key" $BOX_SIZE "" --cancel-button "Back" --title "Provide Credentials" 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus = 0 ]; then
        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    elif [ $exitstatus = 1 ]; then
        selectIdentity
    else
        operationCanceled
    fi
}

provideSecretAccessKey() {
    AWS_SECRET_ACCESS_KEY=$(whiptail --passwordbox "Provide AWS Access Secret Key" $BOX_SIZE "" --cancel-button "Back" --title "Provide Credentials" 3>&1 1>&2 2>&3)
    # A trick to swap stdout and stderr.
    # Again, you can pack this inside if, but it seems really long for some 80-col terminal users.

    exitstatus=$?
    if [ $exitstatus = 0 ]; then
        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    elif [ $exitstatus = 1 ]; then
        selectIdentity
    else
        operationCanceled
    fi
}

saveCredentials() {
    if test -z "$1"; then
        echo "No AWS_ACCESS_KEY_ID provided, exiting..."
        exit 1
    else
        if test -z "$(cat $CREDENTIALS_FILE | grep "$1")"; then
            if (whiptail --title "Save Credentials" --yesno "Save your AWS_ACCESS_KEY_ID for future use?" $BOX_SIZE); then
                echo $1 >>$CREDENTIALS_FILE
            else
                echo "User selected No, exit status was $?."
            fi
        else
            echo "User provided same credentials before, skipping"
        fi
    fi
}

saveIdentity() {
    ACCOUNT_INFO=$(aws sts get-caller-identity)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $IDENTITY
    else
        whiptail --title "Account Information" --msgbox "Bad credentials entered, exiting..." $BOX_SIZE
        echo "Bad credentials entered, exiting"
        exit 1
    fi
    ACCOUNT_ID=$(echo $ACCOUNT_INFO | jq -r ".Account")
    USER_NAME=$(echo $ACCOUNT_INFO | jq -r ".Arn" | cut -d "/" -f 2)

    saveCredentials "$AWS_ACCESS_KEY_ID $ACCOUNT_ID:$USER_NAME"

    whiptail --title "Account Information" --msgbox "Account ID: $ACCOUNT_ID \nUser Name: ${USER_NAME}" $BOX_SIZE
}

viewSecret() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    TEMP_FILE_PATH=$TEMP_DIR/temp_secret.txt

    aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text >$TEMP_FILE_PATH

    whiptail --title "Secret Value: $SECRET_NAME" --scrolltext --textbox $TEMP_FILE_PATH $LINES $COLUMNS $(($LINES - 8))

    selectSecret $SECRET_NAME
}

publishSecret() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    FILEPATH=$SAVED_SECRETS_DIR/$SECRET_NAME

    SECRET_VALUE=$(cat $FILEPATH || echo "Error")

    if [ "$SECRET_VALUE" == "Error" ]; then
        if (whiptail --title "Secret not saved locally: $SECRET_NAME" --yesno "Do you want to save the secret and edit it?" $BOX_SIZE); then
            editSecret $SECRET_NAME
        fi
    else
        if (whiptail --title "Secret to be published: $SECRET_NAME" --yesno "Note: Make sure you review the secret value before approving this dialog. Do you want to publish secret value currently stored in edited file?" $BOX_SIZE); then
            whiptail --title "Saving Secret Backup: $SECRET_NAME" --msgbox "Saving a secret backup before updating the secret value on Secrets Manager" $BOX_SIZE
            mkdir -p $BACKUP_DIR/$SECRET_NAME
            cp $FILEPATH $BACKUP_DIR/$SECRET_NAME/$SECRET_NAME-$(date +"%Y-%m-%d-%T")
            aws secretsmanager put-secret-value --secret-id $SECRET_NAME --secret-string file://$FILEPATH --version-stages "AWSCURRENT" "$(date +"%Y-%m-%d-%T")"
        fi

        selectSecret $SECRET_NAME
    fi
}

editSecret() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    TEMP_FILE_PATH=$TEMP_DIR/temp_secret.txt

    FILEPATH=$SAVED_SECRETS_DIR/$SECRET_NAME

    aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text >$TEMP_FILE_PATH

    cp $TEMP_FILE_PATH $FILEPATH

    code $FILEPATH

    selectSecret $SECRET_NAME
}

saveSecret() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    TEMP_FILE_PATH=$TEMP_DIR/temp_secret.txt

    FILEPATH=$SAVED_SECRETS_DIR/$SECRET_NAME

    aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text >$TEMP_FILE_PATH

    if (whiptail --title "Save Secret: $SECRET_NAME" --yesno --scrolltext "$(cat $TEMP_FILE_PATH)" $LINES $COLUMNS); then
        cp $TEMP_FILE_PATH $FILEPATH
    else
        echo "User selected No, exit status was $?."
    fi

    if (whiptail --title "Saved Secret: $SECRET_NAME" --yesno "Do you want to view saved secret?" $BOX_SIZE); then
        code $FILEPATH
    else
        echo "User selected No, exit status was $?."
    fi

    selectSecret $SECRET_NAME
}

selectSecret() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    CHOSEN_OPTION=$(whiptail --title "Manage Secret: $SECRET_NAME" --menu "Choose an option" $MENU_BOX_OPTIONS \
        "Back" "<-- Go Back" \
        "View" "View Secret Value" \
        "Edit" "Edit Secret Value" \
        "Save" "Save Secret Value. Dir: $SAVED_SECRETS_DIR" \
        "Publish" "Publish Secret Value" \
        "Backups" "View Backups" \
        "Versions" "View Secret Versions" \
        3>&1 1>&2 2>&3)

    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "View" ]; then
            viewSecret $SECRET_NAME

        elif [ $CHOSEN_OPTION == "Edit" ]; then
            editSecret $SECRET_NAME

        elif [ $CHOSEN_OPTION == "Publish" ]; then
            publishSecret $SECRET_NAME

        elif [ $CHOSEN_OPTION == "Save" ]; then
            saveSecret $SECRET_NAME

        elif [ $CHOSEN_OPTION == "Versions" ]; then
            viewVersions $SECRET_NAME

        elif [ $CHOSEN_OPTION == "Backups" ]; then
            listBackups $SECRET_NAME

        elif [ $CHOSEN_OPTION == "Back" ]; then
            listSecrets

            # elif [ $CHOSEN_OPTION == "Create" ]; then

        else
            echo "No option selected"
        fi
    else
        echo "No option selected at identities, exiting..."
        operationCanceled
    fi
}

viewBackup() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Backup File provided" --msgbox "Error on backup file provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        BACKUP_FILE=$2
    fi

    whiptail --title "Secret Backup Value: $SECRET_NAME $BACKUP_FILE" --scrolltext --textbox $BACKUP_DIR/$SECRET_NAME/$BACKUP_FILE $LINES $COLUMNS $(($LINES - 8))

    selectBackup $SECRET_NAME $BACKUP_FILE
}

saveBackupFile() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Backup File provided" --msgbox "Error on backup file provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        BACKUP_FILE=$2
    fi

    BACKUP_FILEPATH=$BACKUP_DIR/$SECRET_NAME/$BACKUP_FILE
    FILEPATH=$SAVED_SECRETS_DIR/$SECRET_NAME

    if (whiptail --title "Save Secret: $SECRET_NAME $BACKUP_FILE" --yesno --scrolltext "$(cat $BACKUP_FILEPATH)" $LINES $COLUMNS); then
        cp $BACKUP_FILEPATH $FILEPATH
    else
        echo "User selected No, exit status was $?."
    fi

    if (whiptail --title "Saved Secret Backup: $SECRET_NAME $BACKUP_FILE" --yesno "Do you want to view saved secret backup?" $BOX_SIZE); then
        code $FILEPATH
    else
        echo "User selected No, exit status was $?."
    fi

    selectBackup $SECRET_NAME $BACKUP_FILE
}

selectBackup() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Backup File provided" --msgbox "Error on backup file provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        BACKUP_FILE=$2
    fi

    CHOSEN_OPTION=$(whiptail --title "Manage Secret Backup: $SECRET_NAME: $BACKUP_FILE" --menu "Choose an option" $MENU_BOX_OPTIONS \
        "Back" "<-- Go Back" \
        "View" "View Secret Backup Value" \
        "Save" "Save Secret Backup Value. Dir: $SAVED_SECRETS_DIR" \
        3>&1 1>&2 2>&3)

    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "View" ]; then
            viewBackup $SECRET_NAME $BACKUP_FILE

        elif [ $CHOSEN_OPTION == "Save" ]; then
            saveBackupFile $SECRET_NAME $BACKUP_FILE

        elif [ $CHOSEN_OPTION == "Back" ]; then
            listBackups $SECRET_NAME

        else
            echo "No option selected"
        fi
    else
        echo "No option selected at identities, exiting..."
        operationCanceled
    fi
}

listBackups() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    INDEX=0
    OPTIONS=""

    #### FIXXXIWIADIWAIDIADIII FIXX WHEN NO REPOOOO ######

    mkdir -p $BACKUP_DIR/$SECRET_NAME

    cd $BACKUP_DIR/$SECRET_NAME

    BACKUP_FILES=$(ls | sort -r)

    if [ "$BACKUP_FILES" != "" ]; then
        for backup in $BACKUP_FILES; do
            OPTIONS="$OPTIONS $((INDEX = $INDEX + 1)) $backup"
        done
    fi

    CHOSEN_OPTION=$(whiptail --title "Secrets Manager" --menu "Choose a secret" $MENU_BOX_OPTIONS "Back" "<-- Go Back" $OPTIONS 3>&1 1>&2 2>&3)

    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "Back" ]; then
            selectSecret $SECRET_NAME
        else
            echo $BACKUP_FILES | cut -d ' ' -f $CHOSEN_OPTION

            selectBackup $SECRET_NAME $(echo $BACKUP_FILES | cut -d ' ' -f $CHOSEN_OPTION)
        fi
    else
        echo "No option selected at secrets manager, exiting..."
        operationCanceled
    fi
}

viewSecretVersion() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Secret Version provided" --msgbox "Error on secret version provided for function selectSecretVersion, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_VERSION=$2
    fi

    TEMP_FILE_PATH=$TEMP_DIR/temp_secret.txt

    echo $SECRET_VERSION

    aws secretsmanager get-secret-value --secret-id $SECRET_NAME --version-id $SECRET_VERSION --query SecretString --output text >$TEMP_FILE_PATH

    whiptail --title "Secret Value: $SECRET_NAME" --scrolltext --textbox $TEMP_FILE_PATH $LINES $COLUMNS $(($LINES - 8))

    selectSecretVersion $SECRET_NAME $SECRET_VERSION
}

makeSecretVersionAsCurrent() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Secret Version provided" --msgbox "Error on secret version provided for function selectSecretVersion, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_VERSION=$2
    fi

    if (whiptail --title "Change Current Secret Version: $SECRET_NAME" --yesno "Do you want to change current secret version to: $SECRET_VERSION" $BOX_SIZE); then
        OLD_VERSION_ID=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --version-stage "AWSCURRENT" --query "VersionId" --output text)
        aws secretsmanager update-secret-version-stage --secret-id $SECRET_NAME --version-stage "AWSCURRENT" --move-to-version-id $SECRET_VERSION --remove-from-version-id $OLD_VERSION_ID
    else
        echo "User selected No, exit status was $?."
    fi

    selectSecretVersion $SECRET_NAME $SECRET_VERSION
}

saveSecretVersion() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Secret Version provided" --msgbox "Error on secret version provided for function saveSecretVersion, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_VERSION=$2
    fi

    TEMP_FILE_PATH=$TEMP_DIR/temp_secret.txt

    FILEPATH=$SAVED_SECRETS_DIR/$SECRET_NAME

    aws secretsmanager get-secret-value --secret-id $SECRET_NAME --version-id $SECRET_VERSION --query SecretString --output text >$TEMP_FILE_PATH

    if (whiptail --title "Save Secret Version: $SECRET_NAME $SECRET_VERSION" --yesno --scrolltext "$(cat $TEMP_FILE_PATH)" $LINES $COLUMNS); then
        cp $TEMP_FILE_PATH $FILEPATH
    else
        echo "User selected No, exit status was $?."
    fi

    if (whiptail --title "Saved Secret Version: $SECRET_NAME $SECRET_VERSION" --yesno "Do you want to view saved secret version?" $BOX_SIZE); then
        code $FILEPATH
    else
        echo "User selected No, exit status was $?."
    fi

    selectSecretVersion $SECRET_NAME $SECRET_VERSION
}

selectSecretVersion() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    if test -z "$2"; then
        whiptail --title "No Secret Version provided" --msgbox "Error on secret version provided for function selectSecretVersion, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_VERSION=$2
    fi

    CHOSEN_OPTION=$(whiptail --title "Manage Secret Version: $SECRET_NAME: $SECRET_VERSION" --menu "Choose an option" $MENU_BOX_OPTIONS \
        "Back" "<-- Go Back" \
        "View" "View Secret Version Value" \
        "Save" "Save Secret Version Value. Dir: $SAVED_SECRETS_DIR" \
        "Current" "Make Secret Version Value as Current Value" \
        3>&1 1>&2 2>&3)

    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "View" ]; then
            viewSecretVersion $SECRET_NAME $SECRET_VERSION

        elif [ $CHOSEN_OPTION == "Current" ]; then
            makeSecretVersionAsCurrent $SECRET_NAME $SECRET_VERSION

        elif [ $CHOSEN_OPTION == "Save" ]; then
            saveSecretVersion $SECRET_NAME $SECRET_VERSION

        elif [ $CHOSEN_OPTION == "Back" ]; then
            viewVersions $SECRET_NAME

        else
            echo "No option selected"
        fi
    else
        echo "No option selected at identities, exiting..."
        operationCanceled
    fi

}

viewVersions() {
    if test -z "$1"; then
        whiptail --title "No Secret Name provided" --msgbox "Error on secret name provided for function, exiting..." $BOX_SIZE
        echo "Exiting..."
        exit 1
    else
        SECRET_NAME=$1
    fi

    SECRET_VERSIONS=$(aws secretsmanager list-secret-version-ids --secret-id $SECRET_NAME --query "Versions")

    OPTIONS=$(echo $SECRET_VERSIONS | jq --raw-output '.[] | .VersionId, .VersionStages | tostring')

    CHOSEN_OPTION=$(whiptail --title "Secrets Manager Versions: $SECRET_NAME" --menu "Choose a secret" $MENU_BOX_OPTIONS "Back" "<-- Go Back" $OPTIONS 3>&1 1>&2 2>&3)

    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "Back" ]; then
            selectSecret $SECRET_NAME
        else
            selectSecretVersion $SECRET_NAME $CHOSEN_OPTION
        fi
    else
        echo "No option selected at secrets manager, exiting..."
        operationCanceled
    fi
}

listSecrets() {
    INDEX=0

    SECRETS=$(aws secretsmanager list-secrets --query SecretList | jq --raw-output '.[].Name')
    OPTIONS=""
    for secretName in $SECRETS; do
        OPTIONS="$OPTIONS $((INDEX = $INDEX + 1)) $secretName"
    done

    CHOSEN_OPTION=$(whiptail --title "Secrets Manager" --menu "Choose a secret" $MENU_BOX_OPTIONS "Back" "<-- Go Back" $OPTIONS 3>&1 1>&2 2>&3)

    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "Back" ]; then
            selectIdentity
        else
            selectSecret $(echo $SECRETS | cut -d ' ' -f $CHOSEN_OPTION)
        fi
    else
        echo "No option selected at secrets manager, exiting..."
        operationCanceled
    fi

}

selectIdentity() {
    OPTIONS=""

    while read -r line; do
        OPTIONS="$OPTIONS $line"
    done <$CREDENTIALS_FILE

    CHOSEN_OPTION=$(whiptail --title "Saved Credentials" --menu "Choose credentials" $MENU_BOX_OPTIONS "Create" "Create new credentials" "Continue" "Continue with your AWS saved configuration" $OPTIONS 3>&1 1>&2 2>&3)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo $EXIT_CODE
        if [ $CHOSEN_OPTION == "Create" ]; then
            provideAccessKeyId
            provideSecretAccessKey

            saveIdentity
        elif [ $CHOSEN_OPTION == "Continue" ]; then
            echo "User continued with AWS saved configuration... Resetting credentials"
            unset AWS_ACCESS_KEY_ID
            unset AWS_SECRET_ACCESS_KEY
        else
            export AWS_ACCESS_KEY_ID=$CHOSEN_OPTION
            provideSecretAccessKey
        fi
    else
        echo "No option selected at identities, exiting..."
        operationCanceled
    fi

    listSecrets
}

main() {
    init

    selectIdentity
}

main
