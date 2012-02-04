#!/bin/sh

DIR=$(dirname $(readlink -f "${0}"))

MACHINE_NAME=`uname -m`
case ${MACHINE_NAME} in
i486|i586|i686)
  MACHINE_NAME=32
  ;;
x86_64)
  MACHINE_NAME=64
  ;;
*)
  MACHINE_NAME=
  ;;
esac

SYSTEM_NAME=`uname -s`

case ${SYSTEM_NAME} in
Linux)
  SYSTEM_NAME=linux
  ;;
*)
  SYSTEM_NAME=unknown_
  ;;
esac


if [ -x ${DIR}/bin/${SYSTEM_NAME}${MACHINE_NAME}/luajit ]
then
  cd ${DIR}
  ./bin/${SYSTEM_NAME}${MACHINE_NAME}/luajit main.lua $*
else
  echo "Your platform does not have a pre-compiled Cheetah engine."
  exit 1
fi