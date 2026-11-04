#!/bin/zsh
# Print one or more 4x6 label PDFs on lg-station-3's ZD420 (raw ZPL, rotated 180). Usage: tools-print-labels-station3.sh a.pdf [b.pdf ...]
set -e
HOST=lynci@100.114.213.100; KEY=~/.ssh/id_ed25519_mini; D=$(mktemp -d); HERE=${0:a:h}
LIST=""; i=0
for pdf in "$@"; do i=$((i+1)); python3 "$HERE/tools-pdf2zpl.py" "$pdf" "$D/lbl-$i.zpl"; LIST="$LIST,'C:\\LG\\lbl-$i.zpl'"; done
cat > "$D/print-labels.ps1" <<PS
\$q = 'ZDesigner ZD420-300dpi ZPL'
foreach (\$f in @(${LIST#,})) { \$zpl = Get-Content -Raw -Path \$f; "\$f : " + (& 'C:\LG\send-zpl.ps1' -Printer \$q -Zpl \$zpl); Start-Sleep -Seconds 5 }
Start-Sleep -Seconds 5
"jobs left: " + (Get-PrintJob -PrinterName \$q | Measure-Object).Count
PS
# NO Get-Printer in the runner: it hangs for minutes over ssh. The Windows ssh shell is PowerShell: no '&' chaining.
scp -q -i $KEY "$D"/lbl-*.zpl "$D/print-labels.ps1" "$HERE/send-zpl.ps1" $HOST:C:/LG/
ssh -i $KEY $HOST "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\LG\\print-labels.ps1" 2>&1 | grep -v -i "post-quantum\|decrypt later\|openssh.com/pq\|^\*\*\s*$"
