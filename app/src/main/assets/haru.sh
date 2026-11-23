#!/system/bin/sh
P=/sys/devices/system/cpu/cpufreq

gov() {
  for p in $P/policy*; do
    av=" $(cat $p/scaling_available_governors 2>/dev/null) "
    for g in "$@"; do
      case "$av" in *" $g "*) echo "$g" > $p/scaling_governor 2>/dev/null; break ;; esac
    done
  done
}
restore() {
  for p in $P/policy*; do
    cat $p/cpuinfo_max_freq > $p/scaling_max_freq 2>/dev/null
    cat $p/cpuinfo_min_freq > $p/scaling_min_freq 2>/dev/null
  done
}
cap() {
  for p in $P/policy*; do
    mn=$(cat $p/cpuinfo_min_freq 2>/dev/null)
    mx=$(cat $p/cpuinfo_max_freq 2>/dev/null)
    [ -n "$mx" ] || continue
    echo "$mn" > $p/scaling_min_freq 2>/dev/null
    echo $((mx * $1 / 100)) > $p/scaling_max_freq 2>/dev/null
  done
}
clean() {
  am kill-all >/dev/null 2>&1
  sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
}

case "$1" in
  powersave)   restore; gov schedutil walt interactive ondemand; cap 60 ;;
  balanced)    restore; gov schedutil walt interactive ondemand ;;
  performance) restore; gov performance schedutil walt ;;
  gaming)      restore; gov performance schedutil walt; clean ;;
  cooldown)
    restore; gov schedutil walt interactive ondemand; cap 50
    nohup sh "$0" cooldown_end >/dev/null 2>&1 &
    ;;
  cooldown_end) sleep 120; restore; gov schedutil walt interactive ondemand ;;
  clear)       clean ;;
esac
exit 0
