#!/bin/bash

# temporary allow a domain for x minutes
# usage: temp-allow.sh shopping.com 5

# Gravity database file
GRAVITY_DB='/etc/pihole/gravity.db'

# Add domain to this group:
# 0 = Default
GROUP_ID=0

# Types:
# 1 = blocklist
# 2 = whitelist
# 3 = regex blocklist
# 4 = regex whitelist
TYPE=2

# reload pihole lists (pihole restartdns reload-lists)
# Not sure that this is needed as we are adding entries directly to gravity database
# It does clear the cache to force a fresh look at the domain..
RELOAD_LISTS=1


# FUNCTIONS

reload_lists() {
  if [ -n "$RELOAD_LISTS" ]; then
    echo "Reloading pihole lists..."
    sudo pihole restartdns reload-lists
  fi
}



# PROGRAM START

# Check arguments:
if [ $# -ne 2 ]; then
  echo "Invalid number of arguments."
  echo "usage: $(basename $0) site time"
  exit 1
fi

# Check DNS name for validity
# Note that internatinal domains won't work here but are valid..
if [[ "$1" =~ ^(([a-zA-Z](-?[a-zA-Z0-9])*)\.)+[a-zA-Z]{2,}$ ]] ; then
  DNS_VALID=1
else
  echo "Invalid DNS name: '$1'"
  exit 1
fi

# Check time
if [[ "$2" =~ ^[0-9]+$ ]]; then
  TIME_VALID=1
else
  echo "Invalid time!  Must be a whole number of minutes."
  exit 1
fi

DOMAIN="$1"
TIME="$(($2*60))"

# see if domain is already in allow list, refuse to add it again

COUNT="$(echo "select count(*) from domainlist where type = 1 and domain = '$DOMAIN'" | sqlite3 "$GRAVITY_DB" 2>&1)"
if [ "$COUNT" -ne 0 ]; then
  echo "Site $DOMAIN already exists in whitelist.  Not whitelisting again."
  exit 1
fi

# Add domain to white list
echo "Adding $DOMAIN to whitelist..."
RESULT="$(echo "insert into domainlist (type,domain,enabled) values ($TYPE,'$DOMAIN',1);" | sqlite3 "$GRAVITY_DB" 2>&1)"

# Get ID for domain
ID="$(echo "select id from domainlist where type = $TYPE and domain = '$DOMAIN';" | sqlite3 "$GRAVITY_DB" 2>&1)"
if [[ "$ID" =~ [0-9]+ ]]; then
  echo "Sucessfully added domain ID $ID..."
else
  echo "Failed to add domain: '$RESULT'"
  exit 1
fi

# add to Default group
RESULT1="$(echo "insert into domainlist_by_group (domainlist_id,group_id) values ($ID,$GROUP_ID);" | sqlite3 "$GRAVITY_DB" 2>&1)"
GROUP_COUNT="$(echo "select count(*) from domainlist_by_group where domainlist_id = '$ID';" | sqlite3 "$GRAVITY_DB" 2>&1)"
if [ "$GROUP_COUNT" -ge 1 ]; then
  echo "Sucessfully added domain to group: $GROUP_ID"
else
  echo "Failed to add domain to group: '$RESULT1'"
exit 1
fi

# Reload pihole lists
reload_lists

# Sleep for the time the site remains unblocked...
echo "Sleeping $TIME Seconds.  Do not close window or site will remain unblocked."
sleep $TIME

# remove site from whitelist
echo "Time expired.  Removing $DOMAIN from whitelist..."
RESULT="$(echo "delete from domainlist where ID = '$ID';" | sqlite3 "$GRAVITY_DB" 2>&1)"
RESULT1="$(echo "delete from domainlist_by_group where domainlist_id = '$ID';" | sqlite3 "$GRAVITY_DB" 2>&1)"

# Reload pihole lists
reload_lists

echo "done."
