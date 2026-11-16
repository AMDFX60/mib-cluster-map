#!/bin/bash
# The part of tests/neon/run.sh that runs in its container: /repo is the
# repository (read only), /t the cache volume.
set -euo pipefail
MODE=${1:-test}
QV=9.2.0
QSHA=f859f0bc65e1f533d040bbe8c92bcfecee5af2c921a6687c652fb44d089bd894
FV=6.1.5
FSHA=b8c8e926b948c14df1264cd0beac1c773df9170ac9cac97bdf1275cd3d385902
Q="/t/qemu/build/qemu-arm -cpu cortex-a9"
N=$(nproc)
mkdir -p /t/dl /t/res
cd /t

# --- QEMU for ARM with the unit's alignment checks --------------------------
if [ ! -x /t/qemu/build/qemu-arm ] || ! cmp -s /repo/tests/neon/qemu_strict.py /t/qemu/.patched-by; then
  echo "building QEMU $QV (a few minutes, once)"
  [ -f dl/qemu-$QV.tar.xz ] || curl -fsSL --retry 3 -o dl/qemu-$QV.tar.xz https://download.qemu.org/qemu-$QV.tar.xz
  echo "$QSHA  dl/qemu-$QV.tar.xz" | sha256sum -c - > /dev/null
  rm -rf /t/qemu && mkdir -p /t/qemu
  tar xf dl/qemu-$QV.tar.xz -C /t/qemu --strip-components=1
  python3 /repo/tests/neon/qemu_strict.py /t/qemu
  mkdir -p /t/qemu/build
  (cd /t/qemu/build && ../configure --target-list=arm-linux-user --enable-plugins --disable-docs \
     --disable-werror > /t/qemu-configure.log 2>&1 && make -j"$N" > /t/qemu-make.log 2>&1)
  cp /repo/tests/neon/qemu_strict.py /t/qemu/.patched-by
fi
gcc -O2 -shared -fPIC -I/t/qemu/include/qemu $(pkg-config --cflags glib-2.0) \
  /repo/tests/neon/fprof.c -o /t/libfprof.so

# --- FFmpeg for a Cortex-A9 with the car's flags, three ways ----------------
#   orig  NEON as FFmpeg ships it (what crashed in the car in 1.3.0-beta2)
#   c6    1.4.0: the six misaligned routines not used (FFmpeg's C code)
#   new   tools/ffmpeg_patches.py applied (as now shipped)
[ -f dl/ffmpeg-$FV.tar.gz ] || curl -fsSL --retry 3 -o dl/ffmpeg-$FV.tar.gz https://ffmpeg.org/releases/ffmpeg-$FV.tar.gz
echo "$FSHA  dl/ffmpeg-$FV.tar.gz" | sha256sum -c - > /dev/null
STAMP=$(cat /repo/tools/ffmpeg_patches.py /repo/tools/ffmpeg_*.patch | md5sum | cut -c1-32)
SIX='ff_(h264_h_loop_filter_(luma|chroma|chroma422)|(put|avg)_h264_chroma_mc[24]|pred8x8_plane)_neon;'
for var in orig c6 new; do
  D=/t/ff-$var
  if [ "$(cat $D/.stamp 2>/dev/null)" != "$STAMP" ]; then
    echo "building FFmpeg $FV ($var)"
    rm -rf $D && mkdir -p $D
    tar xf dl/ffmpeg-$FV.tar.gz -C $D --strip-components=1
    case $var in
      new) python3 /repo/tools/ffmpeg_patches.py $D > /dev/null ;;
      c6)  for f in h264dsp h264chroma h264pred; do
             sed -i -E "s/[ch]->[A-Za-z0-9_]+(\[[A-Za-z0-9_]+\])? *= *$SIX/;/" $D/libavcodec/arm/${f}_init_arm.c
           done
           if grep -qE "$SIX" $D/libavcodec/arm/*_init_arm.c; then
             echo "c6: an assignment of the six routines is left"; exit 1
           fi ;;
    esac
    (cd $D && ./configure --arch=arm --cpu=cortex-a9 --target-os=linux --enable-cross-compile \
       --cross-prefix=arm-linux-gnueabihf- --enable-neon --disable-fast-unaligned \
       --extra-cflags="-marm -mfpu=neon -mno-unaligned-access" --extra-ldflags=-static \
       --disable-doc --disable-programs --disable-avdevice --disable-swresample --disable-swscale \
       --disable-postproc --disable-avfilter --disable-everything --enable-decoder=h264 \
       --enable-parser=h264 --disable-stripping > /t/ff-$var.configure.log &&
     grep -q "HAVE_NEON 1" config.h && grep -q "HAVE_FAST_UNALIGNED 0" config.h &&
     make -j"$N" > /t/ff-$var.make.log 2>&1 && make -j"$N" checkasm >> /t/ff-$var.make.log 2>&1)
    echo "$STAMP" > $D/.stamp
  fi
  arm-linux-gnueabihf-gcc -O2 -marm -I$D /repo/tests/neon/dectest.c $D/libavcodec/libavcodec.a \
    $D/libavutil/libavutil.a -static -lm -lpthread -o /t/dectest-$var
  arm-linux-gnueabihf-nm -S -n --defined-only /t/dectest-$var > /t/dectest-$var.syms
done

# --- Test streams: 1280x720, 30 fps, no B pictures, as Android Auto sends --
if [ ! -f /t/streams/.done ]; then
  echo "making test streams"
  rm -rf /t/streams && mkdir -p /t/streams && cd /t/streams
  X="-pix_fmt yuv420p -an -f h264"
  ffmpeg -y -v error -f lavfi -i testsrc2=s=1280x720:r=30 -t 10 -c:v libx264 -profile:v baseline \
    -x264-params partitions=all:keyint=60:bframes=0 -b:v 2M $X t1_base.h264
  ffmpeg -y -v error -f lavfi -i mandelbrot=s=1280x720:r=30 -t 5 -c:v libx264 -profile:v high \
    -x264-params partitions=all:8x8dct=1:bframes=0:keyint=60:deblock=-1,-1 -crf 22 $X t2_high.h264
  # The cockpit photos panned and turned in the 1010x376 window on black
  # where the phone draws the cluster map in the 720p frame.
  map() { # name photo bitrate [x264 options]
    ffmpeg -y -v error -f lavfi -i color=black:s=1280x720:r=30 -loop 1 -framerate 30 \
      -i /repo/docs/images/cockpit-$2.jpg -filter_complex \
      "[1]scale=3840:-2,crop=1400:700:x='1200+900*sin(t/6)':y='300+250*sin(t/4)',rotate='0.2*sin(t/5)':ow=1010:oh=376[m];[0][m]overlay=135:172" \
      -t 20 -c:v libx264 -profile:v baseline -x264-params partitions=all:keyint=600:bframes=0${4:-} \
      -b:v $3 $X $1.h264
  }
  map t3_map_day day 1500k
  map t3_map_night night 800k
  map t4_map_low day 300k
  map t6_map_slices day 1500k :slices=4
  ffmpeg -y -v error -f lavfi -i testsrc2=s=1280x720:r=30 -t 3 -c:v libx264 -profile:v baseline \
    -x264-params keyint=1 -crf 30 $X t5_intra.h264
  touch .done
  cd /t
fi
STREAMS=$(ls /t/streams/*.h264)

where() { # variant errfile: the function and instruction of a fault
  local pc
  pc=$(sed -n 's/.*pc=\(0x[0-9a-f]*\).*/\1/p' $2)
  [ -n "$pc" ] || { echo "no fault line"; return; }
  echo "$(perl -e '$pc = hex shift; while (<>) { if (/^([0-9a-f]+) [0-9a-f]+ [Tt] (\S+)/) { last if hex($1) > $pc; $n = $2 } } print $n' $pc /t/dectest-$1.syms):" \
       "$(arm-linux-gnueabihf-objdump -d --start-address=$pc --stop-address=$((pc + 4)) /t/dectest-$1 | tail -1 | cut -f3- | tr '\t' ' ')"
}
range() { # the code address range of FFmpeg in a dectest binary
  perl -ne 'if (/^([0-9a-f]+) ([0-9a-f]+) [Tt] (ff_|av_|avcodec_|avpriv_|avutil_)/) { $a = hex $1; $e = $a + hex $2;
    $lo = $a if !defined $lo || $a < $lo; $hi = $e if $e > $hi } END { printf "%x-%x", $lo, $hi }' /t/dectest-$1.syms
}

if [ "$MODE" = test ] || [ "$MODE" = all ]; then
  # Per stream:
  #   ref    C code only (no NEON): the pictures every other run must give
  #   c6     1.4.0, NEON accesses checked as the unit does
  #   new    as shipped now, NEON accesses checked as the unit does
  #   newT2  the same with the player's two slice threads (reference: C code
  #          with two threads; FFmpeg's fast mode then skips filtering
  #          across slice edges, so it differs from one thread on t6)
  #   new2   the same, every access in FFmpeg checked (core loads too)
  #   orig   FFmpeg as shipped, unchecked (as on Linux and Android)
  #   origS  FFmpeg as shipped, checked: must stop as the car did
  rm -f /t/res/*
  r_new=$(range new)
  for f in $STREAMS; do
    s=$(basename $f .h264)
    run() { # tag variant strict args...
      local tag=$1 v=$2 st=$3 rc=0; shift 3
      MIBCM_STRICT_ALIGN=$st MIBCM_STRICT_RANGE=$r_new $Q /t/dectest-$v "$@" \
        > res/$s.$tag.md5 2> res/$s.$tag.err || rc=$?
      echo $rc > res/$s.$tag.rc
    }
    ( run ref new 0 -c $f; run c6 c6 1 $f; run new new 1 $f; run origS orig 1 $f ) &
    ( run refT2 new 0 -c -t 2 $f; run newT2 new 1 -t 2 $f; run new2 new 2 $f; run orig orig 0 $f ) &
    while [ "$(jobs -r | wc -l)" -ge "$N" ]; do wait -n || true; done
  done
  wait
  fail=0
  for f in $STREAMS; do
    s=$(basename $f .h264)
    line="$(printf '%-14s %4s pictures' $s "$(tail -1 res/$s.ref.md5 | cut -d' ' -f2)")"
    for tag in c6 new newT2 new2 orig origS; do
      ref=ref; [ $tag = newT2 ] && ref=refT2
      v=$tag; case $tag in new*) v=new ;; orig*) v=orig ;; esac
      if [ "$(cat res/$s.$tag.rc)" != 0 ]; then
        r="fault in $(where $v res/$s.$tag.err)"
        [ $tag = origS ] && [[ "$r" == *ff_h264_h_loop_filter_luma_neon* ]] || fail=1
      elif cmp -s res/$s.$ref.md5 res/$s.$tag.md5; then
        r="same"
        [ $tag = origS ] && { r="same, NO FAULT (the check does not work)"; fail=1; }
      else
        r="DIFFERENT pictures"; fail=1
      fi
      line="$line | $tag $r"
    done
    echo "$line"
  done
  echo "checkasm (FFmpeg's own test of every DSP routine against C), 10 seeds:"
  for v in new c6 orig; do
    ok=0
    for seed in 1 2 3 4 5 6 7 8 9 10; do
      # In a subshell, so the shell's "Bus error" for orig stays out of sight.
      (MIBCM_STRICT_ALIGN=1 $Q /t/ff-$v/tests/checkasm/checkasm $seed > res/checkasm.$v.out 2>&1; exit $?) 2>/dev/null &&
        grep -q "tests passed" res/checkasm.$v.out && ok=$((ok + 1))
    done
    echo "  $v, NEON accesses checked: $ok/10 seeds passed $(grep -o 'all [0-9]* tests passed' res/checkasm.$v.out || true)"
    case $v in orig) [ $ok = 0 ] || fail=1 ;; *) [ $ok = 10 ] || fail=1 ;; esac
  done
  if [ $fail = 0 ]; then
    echo "PASS: new and c6 give the C code's pictures without a fault; orig stops where the car did"
  else
    echo "FAIL"
    exit 1
  fi
fi

if [ "$MODE" = prof ] || [ "$MODE" = all ]; then
  # Instructions per picture (one decoder thread, no MD5 work): the PC's
  # estimate of decoding time, 1.4.0 (c6) against now (new) and FFmpeg
  # as shipped (orig).
  for f in $STREAMS; do
    s=$(basename $f .h264)
    for v in c6 new orig; do
      $Q -plugin /t/libfprof.so,syms=/t/dectest-$v.syms,out=res/$s.$v.prof /t/dectest-$v -q $f \
        > res/$s.$v.profrun 2>&1 &
      while [ "$(jobs -r | wc -l)" -ge "$N" ]; do wait -n || true; done
    done
  done
  wait
  echo "instructions per picture (millions):"
  for f in $STREAMS; do
    s=$(basename $f .h264)
    n=$(grep -o 'frames [0-9]*' res/$s.c6.profrun | cut -d' ' -f2)
    awk -v s=$s -v n=$n -v a=$(head -1 res/$s.c6.prof | cut -d' ' -f2) \
        -v b=$(head -1 res/$s.new.prof | cut -d' ' -f2) -v c=$(head -1 res/$s.orig.prof | cut -d' ' -f2) \
        'BEGIN { printf "  %-14s 1.4.0 %6.2f   now %6.2f (%4.1f %% fewer)   FFmpeg as shipped %6.2f\n",
                 s, a/n/1e6, b/n/1e6, 100*(a-b)/a, c/n/1e6 }'
  done
fi
