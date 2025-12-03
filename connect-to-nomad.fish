set -x NOMAD_ADDR "http://10.0.0.50:4646"
echo "Nomad address set to $NOMAD_ADDR"
nomad node status