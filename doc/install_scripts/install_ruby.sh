#!/bin/bash
DONE_FLAG="/tmp/$0_done"

echo "#### Install Ruby ####"
if [ -f $DONE_FLAG ]; then exit; fi
echo '-- PRESS ENTER KEY --'
read KEY

ubuntu() {
  echo 'Ubuntu will be supported shortly.'
}

centos() {
  echo "It's CentOS!"

  yum install -y make gcc-c++ bzip2 openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel

  git clone git://github.com/sstephenson/rbenv.git /usr/local/rbenv
  git clone git://github.com/sstephenson/ruby-build.git /usr/local/rbenv/plugins/ruby-build

  echo 'export RBENV_ROOT="/usr/local/rbenv"' >> /etc/profile.d/rbenv.sh
  echo 'export PATH="${RBENV_ROOT}/bin:${PATH}"' >> /etc/profile.d/rbenv.sh
  echo 'eval "$(rbenv init -)"' >> /etc/profile.d/rbenv.sh
  . /etc/profile.d/rbenv.sh

  rbenv install 2.3.7
  rbenv global 2.3.7
  rbenv rehash
  ruby -v

  # bundler
  gem install bundler -v 1.16.1
}

others() {
  echo 'This OS is not supported.'
  exit
}

if [ -f /etc/centos-release ]; then
  centos
elif [ -f /etc/lsb-release ]; then
  if grep -qs Ubuntu /etc/lsb-release; then
    ubuntu
  else
    others
  fi
else
  others
fi

touch $DONE_FLAG
