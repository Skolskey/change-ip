#!/bin/sh
# Regenerate qga-oneliner.txt: a single virsh command with change-ip.sh embedded as base64.
# Run after every change to change-ip.sh.
cd "$(dirname "$0")" || exit 1
B64=$(base64 < change-ip.sh | tr -d '\n')
cat > qga-oneliner.txt <<EOF
VM=myvm OLD=1.2.3.4 NEW=5.6.7.8 GW=; R=\$(virsh qemu-agent-command \$VM "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/sh\",\"arg\":[\"-s\",\"--\",\"\$OLD\",\"\$NEW\",\"\$GW\"],\"capture-output\":true,\"input-data\":\"$B64\"}}") && PID=\$(echo "\$R" | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*\$') && until R=\$(virsh qemu-agent-command \$VM "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":\$PID}}"); echo "\$R" | grep -q '"exited": *true'; do sleep 1; done; for k in out err; do echo "\$R" | grep -o "\"\$k-data\": *\"[^\"]*\"" | cut -d'"' -f4 | base64 -d; done
EOF
# raw guest agent JSON, for panels that pass the text straight to the agent
cat > qga-json.txt <<EOF
{"execute":"guest-exec","arguments":{"path":"/bin/sh","arg":["-s","--","1.2.3.4","5.6.7.8",""],"capture-output":true,"input-data":"$B64"}}
EOF
echo "qga-oneliner.txt: $(wc -c < qga-oneliner.txt) bytes, qga-json.txt: $(wc -c < qga-json.txt) bytes"
