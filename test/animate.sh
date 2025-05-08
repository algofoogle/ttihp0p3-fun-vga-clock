#/!usr/bin/bash

if [ $# -ne 1 ]; then
cat <<EOH
Usage: $0 OUTSPEC
Where:
  OUTSPEC is ONE of:
  - a dir for writing a sequence of PNG files
  - a filename ending in .mp4
  - a filename ending in .gif (animated gif)
  - a double dash (--) for Anton's default behaviour
EOH
exit 1
fi

FRAME_NAME_BASE=frame

# H.264 file
function write_h264() {
    ffmpeg -framerate 60 -i frames_out/$FRAME_NAME_BASE-%03d.ppm -c:v libx264 -r 60 "$1"
}

#NOTE: Call this from within the frames_out dir, like this:
# ../animate.sh frames.gif
function write_animated_gif() {
    #NOTE: GIF delay is in 10ms increments, hence 20fps => 50ms delay => 100/20 = 5 units.
    DELAY=$((100/"${FPS:-1}"))  # Default is 1 frame per second.
    echo "GIF delay is $DELAY unit(s)"
    convert \
        -monitor \
        -delay $DELAY $FRAME_NAME_BASE-???.ppm \
        +antialias -font Ubuntu-Mono -fill white -pointsize 18 -gravity South -annotate 0 '%f' \
        "$1"
}

function anton_default1() {
    outfile="$HOME/HOST_Documents/rbz-$(date +%Y%m%d_%H%M%S).mp4"
    write_h264 "$outfile" \
        && echo "Wrote output file: $outfile" && ls -alh "$outfile" \
        || echo "Failed to write: $outfile"
}

case "$1" in
    # -- was given: Just do a default per Anton's own local testing:
    --)
        anton_default1
        ;;

    # Target .mp4 filename was given:
    *.mp4)
        write_h264 "$1"
        ;;

    # Target .gif filename was given:
    *.gif)
        write_animated_gif "$1"
        ;;

    # Target subdirectory name for discrete PNG files was given:
    *)
        # Convert PPM sequence to PNG sequence in $1 dir:
        # pushd frames_out
        for f in $FRAME_NAME_BASE-???.ppm; do
            echo $f
            convert $f "$1"/$f.png
        done
        # popd
        ;;
esac

