#!/usr/bin/env bash
# Guided enrollment for the Goodix 27c6:55a4 reader. Adapted from
# jith/goodix-55a4-fingerprint scripts/enroll.sh (commit e8ee5bc), unchanged
# except for this header: it only uses fprintd-* and works on any distro.
#   tools/enroll.sh [finger]         new enrollment (replaces your prints), default right-index-finger
#   tools/enroll.sh --add [label]    add 40 more presses of the SAME finger as a second print
set -u
stages=40
add=0
if [ "${1:-}" = "--add" ]; then
  add=1
  shift
fi

if [ $add -eq 1 ]; then
  # fprintd stores one print per finger name; the second print of the same
  # finger needs an unused name (verification checks all of your prints).
  enrolled="$(fprintd-list "$USER" 2>/dev/null)"
  finger="${1:-}"
  if [ -z "$finger" ]; then
    for f in right-middle-finger right-ring-finger right-little-finger right-thumb \
             left-index-finger left-middle-finger left-ring-finger left-little-finger left-thumb; do
      grep -q -- "$f" <<<"$enrolled" || { finger="$f"; break; }
    done
  fi
  [ -n "$finger" ] || { echo "no free finger name left"; exit 1; }
  hints=(
    "your NATURAL touch, exactly as for sudo / unlock"
    "natural touch, slightly more to the LEFT"
    "natural touch, slightly more to the RIGHT"
    "natural touch, slightly towards the TIP"
    "natural touch, slightly LOWER (towards the joint)"
    "natural touch, finger slightly rotated"
    "natural touch, finger a bit flatter"
    "your NATURAL touch again"
  )
  first_press="use a DIFFERENT finger (e.g. your thumb) for this first press"
else
  finger="${1:-right-index-finger}"
  hints=(
    "CENTRE of the fingertip, flat"
    "slightly towards the TIP (~2 mm)"
    "slightly towards the first JOINT (~2 mm)"
    "slightly LEFT"
    "slightly RIGHT"
    "CENTRE, finger rotated slightly LEFT"
    "CENTRE, finger rotated slightly RIGHT"
    "the way you naturally touch it for sudo / unlock"
  )
  first_press="any finger, any placement"
fi

cat <<EOF
== Guided enrollment ($stages presses) for $USER, stored as: $finger
 - Clean, DRY fingertip. Touch LIGHTLY (just cover the sensor) for about half a second,
   then lift fully. Firm presses and sweaty fingers fill the ridge valleys: unclear images.
 - Wait for the "ok" line before the next press.
 - Follow the placement shown before each press; each placement gets 5 presses.
 - "unclear" = press again (lighter, fingertip dry). "lift" = remove the finger first.
 - The first press only checks for an existing print: $first_press.
EOF
if [ $add -eq 1 ]; then
  echo "This ADDS a second print of your right index finger (stored under the name above);"
  echo "all other presses use your right index finger."
else
  echo "This replaces existing prints of $USER."
fi
read -r -p "Press Enter to start... " _
[ $add -eq 1 ] || fprintd-delete "$USER" >/dev/null 2>&1

n=-1   # fprintd reports the duplicate-check press as a stage too
faint=0
echo ">> Press 0 (duplicate check): $first_press"
stdbuf -oL fprintd-enroll -f "$finger" 2>&1 | while IFS= read -r line; do
  case "$line" in
    *enroll-stage-passed*)
      n=$((n + 1)); faint=0
      if [ $n -eq 0 ]; then
        echo "   duplicate check done; press 1 (right index): ${hints[0]}"
      elif [ $n -lt $stages ]; then
        echo "   ok $n/$stages   next: ${hints[$(( n / 5 % ${#hints[@]} ))]}"
      fi ;;
    *enroll-duplicate*)
      echo "   the first press matched your existing print: run the script again and use a"
      echo "   DIFFERENT finger (e.g. thumb) for the first press only" ;;
    *enroll-retry-scan*|*enroll-swipe-too-short*|*enroll-finger-not-centered*)
      faint=$((faint + 1))
      if [ $faint -ge 3 ]; then
        echo "   image unclear again: wipe your fingertip DRY on a cloth and touch more LIGHTLY"; faint=0
      else
        echo "   image unclear: press again at the same spot (lighter, fingertip dry)"
      fi ;;
    *enroll-remove-and-retry*)
      echo "   lift your finger fully, then press again" ;;
    *enroll-completed*)
      echo "== Enrollment completed ($stages presses)" ;;
    *"Enrolling "*)
      : ;;
    *)
      echo "   $line" ;;
  esac
done
fprintd-list "$USER"
echo "Test it: fprintd-verify   (or: sudo -k; sudo true)"
