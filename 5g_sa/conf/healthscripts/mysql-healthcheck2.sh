#!/bin/bash
# MySQL healthcheck for OAI CN5G compose (mounted at /tmp/mysql-healthcheck.sh).
mysqladmin ping -h localhost -uroot -plinux --silent
