#!/bin/bash
#
# banshee2amarok - Convert banshee track play counts and ratings to amarok.
#
# Copyright 2011 Philipp Ittershagen <p.ittershagen@googlemail.com>
#
# Inspired by https://github.com/saschpe/amarok2clementine.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#


BANSHEE_DB=$HOME/.config/banshee-1/banshee.db

AMAROK_DIR=$HOME/.kde4/share/apps/amarok
MYSQL_PID_FILE=/tmp/amarok-mysql-connection.pid

BANSHEE_DUMP_FILE=banshee-dump.txt
AMAROK_OUT_FILE=amarok-output.txt

urldecode() {
	echo -e "$(sed 's/%/\\x/g')"
}

echo "Collecting banshee tracks..."

sqlite3 -separator '	' $BANSHEE_DB \
	"SELECT uri, rating, playcount FROM CoreTracks \
	WHERE rating != 0 or playcount != 0;" \
	> $BANSHEE_DUMP_FILE

echo "$(wc -l $BANSHEE_DUMP_FILE | awk '{print $1}') tracks found."

echo "Connecting to amarok database..."

mysqld --defaults-file=$AMAROK_DIR/my.cnf \
	--default-storage-engine=MyISAM \
	--datadir=$AMAROK_DIR/mysqle \
	--socket=$AMAROK_DIR/sock \
	--pid-file=$MYSQL_PID_FILE \
	--skip-grant-tables --skip-networking &

sleep 3

echo > $AMAROK_OUT_FILE

echo "Searching for corresponding amarok database track entries..."

OLD_IFS=$IFS
IFS="	"

cat $BANSHEE_DUMP_FILE | while read uri rating playcount; do

	amarok_uri=$(echo ".${uri:13}" | urldecode | sed "s/'/\\'/g")

	# Amarok uses a rating of 0-10 (full and half filled stars), whereas banshee
	# uses 0-5 (full stars only). Convert by multiplying by 2.
	rating=$((rating * 2))

	amarok_id=$(mysql --skip-column-names --socket=$AMAROK_DIR/sock amarok -e \
		"SELECT id FROM amarok.urls WHERE rpath=\"${amarok_uri}\";")

	if [ -z "$amarok_id" ]; then
		echo "Skipping Song ${amarok_uri}, because no amarok ID was found for it."
	else
		echo "UPDATE amarok.statistics \
			SET rating = $rating, playcount = $playcount \
			WHERE id = $amarok_id;" >> $AMAROK_OUT_FILE
	fi

done

IFS=$OLD_IFS

mysql --socket=$AMAROK_DIR/sock amarok < $AMAROK_OUT_FILE

echo "Updated $(wc -l $AMAROK_OUT_FILE | awk '{print $1}') songs in the amarok db."

kill $(cat $MYSQL_PID_FILE)

rm -f $AMAROK_OUT_FILE $BANSHEE_DUMP_FILE

