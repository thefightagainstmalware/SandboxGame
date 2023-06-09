#!/usr/bin/env bash
set +H x

validate_user() {
    getent passwd "$1" > /dev/null 2>&1 
    return $?
}

confirm() {
    while true; do
        read -r -p "$1 [y/n] " yn
        if [ $? -eq 1 ]; then
            exit 1
        fi
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

does_not_have_sudo_rights() {
    sudo -l -U "$1" | grep not\ allowed > /dev/null 2>&1
    return $?
}

download_papermc() {
    if [ $# -eq 1 ]; then # download latest server
        paper_mc_ver=$(curl https://api.papermc.io/v2/projects/paper --silent | jq -r '.["versions"][-1]')
        output_dir=$1
    else
        paper_mc_ver=$1
        output_dir=$2
    fi
    echo "Server used: Paper" >> "$mc_server_dir"/summary.txt
    echo "Minecraft server version: $paper_mc_ver" >> "$mc_server_dir"/summary.txt
    download_api_response=$(curl https://api.papermc.io/v2/projects/paper/versions/"$paper_mc_ver"/builds)
    paper_build_number=$(jq -r '.["builds"][-1]["build"]' <<< "$download_api_response")
    echo "Paper build number: $paper_build_number" >> "$mc_server_dir"/summary.txt
    paper_file_name=$(jq -r '.["builds"][-1]["downloads"]["application"]["name"]' <<< "$download_api_response")
    download_url=https://api.papermc.io/v2/projects/paper/versions/"$paper_mc_ver"/builds/"$paper_build_number"/downloads/"$paper_file_name"
    echo "Paper build number: $paper_build_number" >> "$mc_server_dir"/summary.txt
    echo "Paper download URL: $download_url" >> "$mc_server_dir"/summary.txt
    curl -L "$download_url" --silent -o "$output_dir"/server.jar
}

if [ "$(id -u)" != 0 ]; then
  echo "you need to be root to run this script"
  exit 1
fi

if [ -f /sys/module/apparmor/parameters/enabled ] && grep "Y" /sys/module/apparmor/parameters/enabled >/dev/null 2>&1; then
    if confirm "Do you want to create a new user account specifically for running Minecraft? (more secure)"; then
        if validate_user "sandbox_game_minecraft_server" && does_not_have_sudo_rights "sandbox_game_minecraft_server"; then
            if confirm "It appears that we've already created a user called 'sandbox_game_minecraft_server'. Do you want to use it?"; then
                user=sandbox_game_minecraft_server
            else
                num=1
                while true; do
                    if validate_user "sandbox_game_minecraft_server$num"; then
                        echo "Skipping 'sandbox_game_minecraft_server$num' as it already exists"
                    else
                        user="sandbox_game_minecraft_server$num"
                        adduser --disabled-password --gecos "Minecraft server user" $user
                        break
                    fi
                    ((num++))
                done
            fi
        else
            user="sandbox_game_minecraft_server"
            adduser --disabled-password --gecos "Minecraft server user" $user
        fi
    else
        while true; do
            read -r -p "What user runs the Minecraft server? " user

            if validate_user "$user"; then
                if does_not_have_sudo_rights "$user"; then
                    break;
                else
                    echo "'$user' can run some commands as root using sudo. This is not recommended as it is insecure."
                    exit 1
                fi
            fi
        done
    fi
    echo "Using '$user' as the user running the Minecraft server"
    user_homedir=~$user
    uid=$(id -u $user)
    if confirm "Do you want me to create a Minecraft server from scratch? Answer no if you already have a Minecraft server you want to use"; then
        if [ -d "$user_homedir/sandbox_game_minecraft_server" ]; then
            if confirm "It appears that we've already created a Minecraft server in '$user_homedir/sandbox_game_minecraft_server'. Do you want to use it?"; then
                mc_server_dir=$user_homedir/sandbox_game_minecraft_server
            else
                num=1
                while true; do
                    if [ -d "$user_homedir/sandbox_game_minecraft_server$num" ]; then
                        echo "Skipping 'sandbox_game_minecraft_server$num' as it already exists"
                    else
                        mc_server_dir="sandbox_game_minecraft_server$num"
                        mkdir "$mc_server_dir"
                        break
                    fi
                    ((num++))
                done
            fi
        else
            mc_server_dir="$user_homedir/sandbox_game_minecraft_server"
            mkdir "$mc_server_dir"
        fi

        echo "Autocreated Minecraft Server Summary:" > "$mc_server_dir"/summary.txt
        echo "Running user: $" >> "$mc_server_dir"/summary.txt

        if confirm "Do you want to use the PaperMC Minecraft server (recommended if you want a vanilla server)?"; then
            if confirm "Do you want the latest PaperMC Minecraft server?"; then
                download_papermc "$mc_server_dir"

            else
                read -r -p "Enter the Minecraft version that you want to downlaod" mc_ver
                download_papermc "$mc_ver" "$mc_server_dir"
            fi
        else
            read -r -p "Enter the download URL of the server jar " download_url
            curl -L "$download_url" --silent -o "$mc_server_dir"/paper.jar
            echo "Server used: Unknown" >> "$mc_server_dir"/summary.txt
            echo "Minecraft server version: Unknown" >> "$mc_server_dir"/summary.txt
            echo "Paper download URL: $download_url" >> "$mc_server_dir"/summary.txt
        fi
        if confirm "Do you agree to the EULA (https://aka.ms/MinecraftEULA)?"; then
            echo "eula=true" > "$mc_server_dir"/eula.txt
        fi
        echo "We will now create a shell script at '$mc_server_dir/main.sh' to make it easier to run your server. You should be able to add options to it later."
        echo "#!/usr/bin/env bash\n\nif [ \$(whoami) != $user]; then\n    echo "You must run me as $user"\n    exit 1\nfi\njava -jar server.jar" > "$mc_server_dir"/main.sh
        shell_script_path="$mc_server_dir"/main.sh
        chown $user:$user "$mc_server_dir" -R
        echo "Summary (you can read this again at '$mc_server_dir/summary.txt'): "
        cat "$mc_server_dir"/summary.txt
    else
        read -r -p "Enter the directory of the Minecraft server" mc_server_dir
        echo "Changing ownership of '$mc_server_dir' to the user '$user'"
        chown $user:$user "$mc_server_dir" -R
        if confirm "Do you already use a shell script to run your server?";
            read -r -p "Enter the full path of the shell script" shell_path #TODO support relative paths
        else
            echo "We will now create a shell script at '$mc_server_dir/main.sh' to make it easier to run your server. You should be able to add options to it later."
            read -r -p "Enter the path of the jar that we should run"
            echo "#!/usr/bin/env bash\n\nif [ \$(whoami) != $user]; then\n    echo "You must run me as $user"\n    exit 1\nfi\njava -jar " > "$mc_server_dir"/main.sh
            shell_script_path="$mc_server_dir"/main.sh
        fi
    fi
    export uid user_homedir mc_server_dir shell_script_path user

    num=1
    while true; do
        if [ -f /etc/apparmor.d/minecraft-server$num.aa ]; then
            echo "Skipping '/etc/apparmor.d/minecraft-server$num.aa' as it already exists"
        else
            file="/etc/apparmor.d/minecraft-server$num.aa"
            # TODO: possibly freeze this in place?
            curl https://raw.githubusercontent.com/thefightagainstmalware/SandboxGame/main/minecraft-server.aa.template | envsubst > $file
            break
        fi
        ((num++))
    done

    if confirm "Do you want to manage this Minecraft server using systemd (recommended, requires systemd)?"; then
        if ps -p 1 -o comm= | grep systemd; then
            num=1
            while true; do
                if [ -f /etc/systemd/system/minecraft-server$num.service ]; then
                    echo "Skipping '/etc/systemd/system/minecraft-server$num.service' as it already exists"
                else
                    file="/etc/systemd/system/minecraft-server$num.service"
                    # TODO: possibly freeze this in place?
                    curl https://raw.githubusercontent.com/thefightagainstmalware/SandboxGame/main/minecraft-server.service.template | envsubst > $file
                    break
                fi
                ((num++))
            done
        else 
            echo "You are not running systemd."
        fi
    fi
else
    echo "AppArmor is required to run this script. SELinux is not supported yet If you have AppArmor support in your kernel, enable it with 
    sudo systemctl enable apparmor --now"
fi