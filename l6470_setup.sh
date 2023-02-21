#/bin/bash 
target_user=$USER

# append excute permision
for f in *.sh; do
    if [ ${0:2} != $f ]; then
        sudo chmod +x $f
    fi
done

# update & upgrade apt repository
echo "apt update & upgrade"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
sudo apt update -y && sudo apt upgrade -y

# install apt packages 

echo "Instal apt packages"
sudo apt install -y git vim python3-pip 
sudo apt install -y python3-smbus python3-numpy libzmq3-dev libhidapi-hidraw0 libatlas-base-dev
sudo apt install -y i2c-tools pigpio pigpiod
sudo apt install -y nodejs npm
echo "Update PIP"
python3 -m pip install -U pip

echo "Install pip packages"
# install python packages
pip3 install pyzmq smbus hid zmq gpio
pip3 install flask flask-restful flask-cors

echo "NodeJS Package Installing"
sudo npm install -g npm
sudo npm install -g pm2

echo "Allow SSH RootLogin"
# Set allow ssh root login
sudo sed -i "/^#PermitRootLogin/ s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
sudo sed -i "/^#StrictModes/ s/#StrictModes.*/StrictModes yes/" /etc/ssh/sshd_config
sudo service sshd restart

echo "Initial Setup"
# user append in i2c1 group 
sudo adduser $target_user i2c
# user append in root group 
sudo adduser $target_user root
sudo sed "/^root/ a${target_user} 	ALL=(ALL:ALL) ALL" /etc/sudoers

# change user uid and gid for hidlib Permission
root_uid=$(id -u root)
root_gid=$(id -g root)
user_uid=$(id -u ${target_user})
user_gid=$(id -u ${target_user})

sudo sed -i "/^${target_user}:x:*/ s/${target_user}:x:${user_uid}:${user_gid}*/${target_user}:x:${root_uid}:${root_gid}/" /etc/passwd

echo "Clone Github Repo"
git clone -b l6470 https://github.com/heon0226/LabGC-Fly-web.git
git clone -b l6470 https://github.com/heon0226/LabgeniusFly.git