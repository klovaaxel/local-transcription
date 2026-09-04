rm -rf /tmp/debx; mkdir -p /tmp/debx
dpkg-deb -x /mnt/d/Personal/local-transcription/dist/forelasning_1.0.0-1_amd64.deb /tmp/debx
for f in /tmp/debx/opt/forelasning/lib/*.so; do
  echo "== $(basename $f)  SONAME=$(objdump -p "$f" 2>/dev/null | awk '/SONAME/{print $2}')"
  objdump -p "$f" 2>/dev/null | awk '/NEEDED/{printf "   %s\n", $2}'
done
