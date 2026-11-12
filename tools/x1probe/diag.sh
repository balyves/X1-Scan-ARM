#!/bin/zsh
# X1-Scan-ARM : diagnostic d'énumération (lecture seule, n'envoie rien au scanner)
out=~/Desktop/x1-diag-$(date +%Y%m%d-%H%M%S).txt
{
  echo "### Système"; sw_vers; uname -m; echo
  echo "### FireWire (system_profiler)"; system_profiler SPFireWireDataType 2>&1; echo
  echo "### Registre IOKit : Imacon / Hasselblad"
  ioreg -l -w0 | grep -i -B8 -A40 -E "imacon|hasselbl" ; echo
  echo "### Périphériques SCSI (IOSCSIPeripheralDeviceNub)"
  ioreg -l -w0 -r -c IOSCSIPeripheralDeviceNub; echo
  echo "### Nœuds SBP-2"
  ioreg -l -w0 -r -c IOFireWireSBP2LUN 2>/dev/null | head -80; echo
  echo "### Pilotes FireWire chargés"
  kextstat 2>/dev/null | grep -i -E "firewire|sbp2"
  systemextensionsctl list 2>/dev/null | grep -i -E "firewire|asfw"
} > "$out" 2>&1
echo "Rapport enregistré : $out"
