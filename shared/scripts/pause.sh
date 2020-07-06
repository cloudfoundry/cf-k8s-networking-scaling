seconds=${1:-10000000000}

echo "I am paused for ${seconds} seconds, run"
echo "kill $BASHPID"
echo "to continue"

sleep ${seconds}
