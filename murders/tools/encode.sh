#!/bin/sh
# Encode the rendered frames with the original song as the soundtrack.
#   sh murders/tools/encode.sh            -> final/music-video.mp4 (master, CRF 18)
#   sh murders/tools/encode.sh preview    -> out/murders/music-video-preview.mp4 (same format, two-pass to ~28 MB, for sharing)
# The audio is the user's mp3, re-encoded to AAC with no filters, so its samples start at 0 and keep their timing.
set -e
FRAMES=out/murders/frames/%05d.png
SONG=murders/audio/Murders.mp3
COLOR="-vf scale=out_color_matrix=bt709:out_range=tv -colorspace bt709 -color_primaries bt709 -color_trc bt709"
mkdir -p final
if [ "$1" = preview ]; then
  OUT=out/murders/music-video-preview.mp4
  ffmpeg -v error -y -framerate 30 -i $FRAMES -c:v libx264 -preset slow -b:v 840k -pass 1 -passlogfile out/murders/x264pass \
    -profile:v high -pix_fmt yuv420p $COLOR -an -f mp4 /dev/null
  ffmpeg -v error -y -framerate 30 -i $FRAMES -i $SONG -map 0:v -map 1:a -c:v libx264 -preset slow -b:v 840k -pass 2 \
    -passlogfile out/murders/x264pass -profile:v high -pix_fmt yuv420p $COLOR -c:a aac -b:a 160k -movflags +faststart $OUT
else
  OUT=final/music-video.mp4
  ffmpeg -v error -y -framerate 30 -i $FRAMES -i $SONG -map 0:v -map 1:a -c:v libx264 -preset slow -crf 18 \
    -profile:v high -pix_fmt yuv420p $COLOR -c:a aac -b:a 320k -movflags +faststart $OUT
fi
ls -l $OUT
