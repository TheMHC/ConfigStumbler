ConfigStumbler
=====================================

ConfigStumbler is a coax mac/config sniffer. it watches UDP port 68(bootp) for packets of a certain length. It pulls out the config name, tftp ip, mac from this. Then it downloads the config found using tftp.exe and uses docsis.exe to decode the config and pull out speed/bpi information (if possible)