# Quick Reference

## Vault

### Unseal all nodes

for ip in 10.0.0.30 10.0.0.31 10.0.0.32; do ssh $ip "vault operator unseal"; done

## Check status

vault status

## Nomad

### Deploy all services

nomad run jobs/services/*.nomad.hcl

## Watch job

nomad job status -verbose whoami

## Consul

### List services

consul catalog services

## DNS test

dig @10.0.0.50 whoami.service.consul