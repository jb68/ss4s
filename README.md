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
ssh key-less login enabled between host and quest servers
rsync installed on remote server
busy-box, dash, ash, bash on local server

Install
- currently config needs to be in the same dir as the executable script

Config
- will request a global section followed by individoal config for host1,
  host2, hostn sections.
- Please note there is a 2 spaces mandatory indentation and
also all hosts need to be covered as a number.  

Global Config items:
	retDays:  - Retention Days (number) Ex: 7
	retWeeks:  Retention Weekes (number) Ex: 4 
	retMonths:  FRetention Months (number) Ex: 6
	destDir:  Local destionation for backups Ex: /backups
	rsyncRemote:  Path to rsync on remote system. Ex: /usr/bin/rsync
	rsyncLocal:  Path to rsync on local server Ex: /usr/bin/rsync
Host Config items:
	host#: - Host number, basically next number available. So if we have 4 hosts to backup we need to have host1, host2, host3, host4. Adding a new one will create host5. Order is not important, but skiping one number will result in an error.
	alias:  Used for a better identification of server when handling config file
	fqdn:  Fully qualified name or IP of the host. Used by rsync to connect to
    user:  User used to connect to host. Ex: root
	dirs:  Directories to be backup separated by space Ex: /dir1 /path/to/dir2
	excl:  Exclusion directories or files. Ex: /path/to/tmp
	rsync:  Remote RSYNC path if different then the rsyncRemote global config item

---------------------------------------------------------------------

Adding a new server to backup:
On Server:  
	Check for rsync and eventually install it (sudo yum install rsync)
	Under root install ssh key from the backup server
On Backup Server:
	Check password less connection with ssh ( ssh [HostIP] )
	Modify config by adding a new section thst should look like this
host6:
  alias: Jenkins 4A
  fqdn: 192.168.7.51
  user: root
  dirs: /opt /etc
  excl: /etc/webmin/system-status/
  
--------------------------------------------------------------------

S4H - snapshots for homes
- Designed to backup multiple user homes exported from one place
- Based on s4s script but the directory structure is different making easy to
  individually re-export the snapshot directories to users
  
Config will take only 2 sections, local and host.
local:
  retDays: Retention Days (number) Ex: 7
  retWeeks: Retention Weeks (number) Ex: 4
  retMonths: Retention Months (number) Ex: 6
  destDir: Destination Directory for backup Ex: /export/backup/home
  rsync: Path to local rsync. Ex: /usr/bin/rsync

host:
  name: fqdn to NFS server that have homes. Ex: 192.168.1.4
  user: User used to connect to server Ex: root
  rsync: Remote rsync path. Ex: /usr/bin/rsync
  homedir: Path to home directopries : Ex: /export/home
  excl: Exclusion list Ex: .* (no dot files)

