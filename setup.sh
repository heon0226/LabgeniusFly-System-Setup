#/bin/bash 
target_user=$USER

# append excute permision
for f in *.sh; do
    if [ ${0:2} != $f ]; then
        sudo chmod +x $f
    fi
done

echo "Change user to root"

echo "Allow SSH RootLogin"
# Set allow ssh root login
sudo sed -i "/^#PermitRootLogin/ s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
sudo sed -i "/^#StrictModes/ s/#StrictModes.*/StrictModes yes/" /etc/ssh/sshd_config
sudo service sshd restart

echo "Initial Setup"
# user append in i2c group 
sudo adduser $target_user i2c
# user append in root group 
sudo adduser $target_user root
sudo sed "/^root/ a$target_user 	ALL=(ALL:ALL) ALL" /etc/sudoers

# change user uid and gid for hidlib Permission
root_uid=$(id -u root)
root_gid=$(id -g root)
user_uid=$(id -u $target_user)
user_gid=$(id -u $target_user)

sudo sed -i "/^$target_user:x:*/ s/$target_user:x:${user_uid}:${user_gid}*/$target_user:x:${root_uid}:${root_gid}/" /etc/passwd

# update & upgrade apt repository
echo "apt update & upgrade"

sudo apt update && sudo apt upgrade -y

# install apt packages 

echo "Instal apt packages"
sudo apt install -y git vim python3-pip 
sudo apt install -y python3-smbus python3-numpy libzmq3-dev libhidapi-hidraw0 
sudo apt install -y i2c-tools pigpio pigpiod

echo "Update PIP"
sudo python3 -m pip3 install -U pip3

echo "Install pip packages"
# install python packages
pip3 install pyzmq smbus hid zmq gpio
pip3 install flask flask-restful flask-cors

echo "NodeJS Installing"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
sudo apt install nodejs 
sudo npm install -g npm
sudo npm install -g pm2

sudo reboot