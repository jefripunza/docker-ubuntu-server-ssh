#!/bin/bash

docker-compose pull

docker-compose -f docker-compose.yaml up --force-recreate --build -d
# docker-compose -f docker-compose.yaml up --force-recreate --build -d --scale app=3

docker image prune -f
