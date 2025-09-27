#/usr/bin/env bash
wget -O argon1.wget.sh https://download.argon40.com/argon1.sh
lines=$(sdiff -sd argon1.original.sh argon1.wget.sh | wc -l)
if [ $lines -eq 0 ]; then
    echo No Update
    rm argon1.wget.sh
else
    echo Source Updated! Copy from argon1.wget.sh for new script
fi
