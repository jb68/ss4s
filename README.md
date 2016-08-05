# ss4s
Simple Snapshot for Servers will connect to a remote server, create a local
incremental snapshot then rotate them based on a specific retention policy.

Initially written to reside on synology disk station and do daily snapshot backups.
Since the backup server can reside behind a firewall this will add a

Features:
- easy config on YAML file
- snapshot multiple servers
- supports lists for directories to snapshot and for excludes
- exclude multiple files or directories option
- configurable retention policy ex 7-4-6  ( days-weeks-months )
- can be restarted in case of failure and will continues

Requirements:
ssh key-less enabled between host and quest servers
rsync
busy-box, dash, ash, bash

Install
- currently cconfig is supported to be in the same dir as the executable script

Config
- will request a global section followed by host1, host2, hostX sections.
- Host name is currently hard coded.

Global section will take:
- rsync path locations and retention policy

Host section will take:
name : fqdn for that host
user: ex: root .Please test that you can ssh to user@host without password
dirs: list of full paths directories to snapshot separated by a space
excl: list of excludes separated by a space. Please read rsync man

ToDo:
- Add check for last snapshot and exit if last snapshot is to new


