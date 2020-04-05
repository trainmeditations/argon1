#/usr/bin/env bash
wget -O argon1.sh.wget https://download.argon40.com/argon1.sh
lines=$(sdiff -sd argon1.sh.original argon1.sh.wget | wc -l)
if [ $lines == 0 ]; then
    echo No Update
    rm argon1.sh.wget
else
    echo Source Updated! Copy from argon1.sh.wget for new script
fi
