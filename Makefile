.PHONY: setup build up down status open open-1 open-2 ssh-1 ssh-2 logs-1 logs-2

setup:
	./lab setup

build:
	./lab build

up:
	./lab up

down:
	./lab down

status:
	./lab status

open: open-1

open-1:
	./lab open alpine-1

open-2:
	./lab open alpine-2

ssh-1:
	./lab ssh alpine-1

ssh-2:
	./lab ssh alpine-2

logs-1:
	./lab logs alpine-1

logs-2:
	./lab logs alpine-2
