#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Guided FlexColor capture sessions (docs/test-session.md, part G, steps 1-22;
# part H, steps 23-32)
# for the reference Mac (Mojave): bash 3.2 and what macOS ships (lldb from the
# Command Line Tools, screencapture, /usr/bin/python with PyObjC). Nothing to
# install.
#
# This script never talks to the X1. It only starts FlexColor under lldb
# with tools/capture/cap3.py (read-only breakpoints), shows each step, notes
# the time and takes screenshots. Only FlexColor talks to the scanner.
#
# Usage:
#   tools/capture/guided-session.sh                 part G, from step 1
#   tools/capture/guided-session.sh --part H        part H (steps 23-32)
#   tools/capture/guided-session.sh --from 8        resume at step 8 (to the
#                                                   end of that step's part)
#   tools/capture/guided-session.sh --list          list the steps
# The output folder is named after the day: to resume on another day, give
# the first day's folder with X1GUIDE_DIR.
# Environment (optional):
#   X1GUIDE_FLEXCOLOR   FlexColor executable
#                       (default: /Applications/FlexColor 4.8.13/FlexColor.app/Contents/MacOS/FlexColor)
#   X1GUIDE_CAP3        path of cap3.py (default: next to this script; the file
#                       must be named cap3.py, its callbacks are cap3.<name>)
#   X1GUIDE_DIR         output folder (default: ~/Desktop/captures-YYYY-MM-DD)
#   X1CAP_SCAN_MB       image data kept after each SCAN, in MiB (default: 64, as
#                       in docs/test-session.md C2; expected to hold every scan of
#                       parts G and H whole: check "RAW skipped" in the logs)
#   X1GUIDE_DRY_RUN=1   try the script without FlexColor nor lldb: a placeholder
#                       process stands for FlexColor, Entrée "quits" it, the
#                       screenshots are empty files, and the default folder is
#                       ~/Desktop/captures-YYYY-MM-DD-essai-a-blanc.

set -u

DRY_RUN=${X1GUIDE_DRY_RUN:-0}
FLEXCOLOR=${X1GUIDE_FLEXCOLOR:-"/Applications/FlexColor 4.8.13/FlexColor.app/Contents/MacOS/FlexColor"}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAP3=${X1GUIDE_CAP3:-"$SCRIPT_DIR/cap3.py"}
if [ "$DRY_RUN" = 1 ]; then
    DIR=${X1GUIDE_DIR:-"$HOME/Desktop/captures-$(date +%Y-%m-%d)-essai-a-blanc"}
else
    DIR=${X1GUIDE_DIR:-"$HOME/Desktop/captures-$(date +%Y-%m-%d)"}
fi
SCAN_MB=${X1CAP_SCAN_MB:-64}
NOTES="$DIR/essai-notes.txt"
PART_G_LAST=22  # part G: steps 1-22; part H: steps 23-LAST_STEP
LAST_STEP=32
CURRENT_STEP=1

CAPTURE=""      # name of the capture running (essai-I, essai-J1...), "" if none
LLDB_PID=""

# ---------------------------------------------------------------------------
# Output helpers

say() { printf '%s\n' "$*"; }

banner() {
    say ""
    say "=================================================================="
    say "$*"
    say "=================================================================="
}

state() {  # state X1 FLEXCOLOR
    say "  X1 : $1    FlexColor : $2"
}

note() {  # note TEXT: one line with the time in essai-notes.txt
    printf '%s  %s\n' "$(date +%H:%M:%S)" "$*" >> "$NOTES"
}

wait_enter() {  # wait_enter PROMPT
    # Drop keys typed while waiting (an Entrée pressed during a long scan must
    # not answer the next question). Only on a terminal.
    if [ -t 0 ]; then
        while read -r -t 1 _; do :; done
    fi
    printf '%s ' "${1:-Entrée pour continuer.}"
    if ! read -r _; then
        say ""
        say "Entrée standard fermée : arrêt du guide."
        stop_guide 1
    fi
}

ask_yes() {  # ask_yes QUESTION: true for "o"
    local answer
    if [ -t 0 ]; then
        while read -r -t 1 _; do :; done
    fi
    printf '%s (o/n) ' "$1"
    if ! read -r answer; then
        say ""
        say "Entrée standard fermée : arrêt du guide."
        stop_guide 1
    fi
    case $answer in o|O|oui|Oui) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# FlexColor under lldb

capture_alive() {  # the lldb run of the current capture is still going
    [ -n "$LLDB_PID" ] && kill -0 "$LLDB_PID" 2>/dev/null
}

flexcolor_running() {
    if [ "$DRY_RUN" = 1 ]; then
        capture_alive
    else
        pgrep -x FlexColor >/dev/null 2>&1
    fi
}

unique_name() {  # unique_name BASE: BASE, or BASE-2, BASE-3... if a log or data file exists
    local name=$1 n=2
    while [ -e "$DIR/$name.txt" ] || [ -e "$DIR/$name.raw" ]; do
        name="$1-$n"
        n=$((n + 1))
    done
    printf '%s' "$name"
}

start_capture() {  # start_capture BASE: FlexColor under lldb + cap3.py, log BASE.txt, data BASE.raw
    if flexcolor_running; then
        say ""
        state "allumé" "à quitter"
        say "FlexColor tourne déjà. Quittez-le (FlexColor > Quitter), puis Entrée."
        say "(Un seul programme peut ouvrir le scanner à la fois.)"
        while flexcolor_running; do wait_enter "Entrée quand FlexColor est fermé."; done
    fi
    CAPTURE=$(unique_name "$1")
    local log="$DIR/$CAPTURE.txt"
    note "capture $CAPTURE : lancement de FlexColor sous lldb (cap3.py, X1CAP_SCAN_MB=$SCAN_MB)"
    if [ "$DRY_RUN" = 1 ]; then
        say "[essai à blanc] FlexColor simulé pour $CAPTURE"
        printf 'dry run: %s\n' "$CAPTURE" > "$log"
        : > "$DIR/$CAPTURE.raw"
        sleep 100000 </dev/null >/dev/null 2>&1 &
        LLDB_PID=$!
        return
    fi
    # As in docs/test-session.md C2, with --batch: lldb quits when FlexColor
    # exits (and after a crash, -k). stdin from /dev/null: lldb in the
    # background must not read the terminal. set -m: lldb gets its own process
    # group, so a Ctrl-C in this terminal reaches the guide only, not lldb
    # (which would halt FlexColor and then end the run).
    set -m
    X1CAP_RAW="$DIR/$CAPTURE.raw" X1CAP_SCAN_MB="$SCAN_MB" \
        lldb --arch i386 --batch \
            -o "command script import \"$CAP3\"" \
            -o "run" \
            -k "quit" \
            "$FLEXCOLOR" \
            </dev/null >"$log" 2>&1 &
    LLDB_PID=$!
    set +m
    say "FlexColor démarre sous lldb (journal : $log)."
    # cap3.py must have set its breakpoints and its image limit, or the capture is lost (C2).
    local waited=0
    until grep -q "cap3.py : points d arret poses" "$log" 2>/dev/null \
            && grep -q "cap3.py : X1CAP_SCAN_MB=" "$log" 2>/dev/null; do
        if ! capture_alive || [ "$waited" -ge 60 ]; then
            say ""
            say "ATTENTION : cap3.py n'a pas posé ses points d'arrêt ou sa limite d'image (voir $log)."
            say "Rien n'est capturé. Quittez FlexColor s'il s'est ouvert, puis relancez"
            say "le guide avec --from $CURRENT_STEP."
            note "capture $CAPTURE : cap3.py incomplet dans le journal, arrêt"
            stop_guide 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    say "Points d'arrêt de cap3.py posés. Attendez que la fenêtre de FlexColor soit ouverte."
}

end_capture() {  # wait for FlexColor to be quit and lldb to exit
    [ -n "$CAPTURE" ] || return 0
    say ""
    if [ "$DRY_RUN" = 1 ]; then
        wait_enter "[essai à blanc] Entrée pour « quitter FlexColor »."
        kill "$LLDB_PID" 2>/dev/null
    elif capture_alive; then
        say "Quittez FlexColor (FlexColor > Quitter, ⌘Q). Le guide attend la fin de lldb..."
    fi
    wait "$LLDB_PID" 2>/dev/null
    local size end="FlexColor quitté, lldb terminé"
    size=$(du -h "$DIR/$CAPTURE.raw" 2>/dev/null | cut -f1 | tr -d ' ')
    if [ "$DRY_RUN" != 1 ] && ! grep -q "exited with status = 0" "$DIR/$CAPTURE.txt" 2>/dev/null; then
        end="ARRÊT ANORMAL de FlexColor ou de lldb (voir la fin de $CAPTURE.txt)"
        say "ATTENTION : $end."
    fi
    note "capture $CAPTURE : $end (${size:-0} de données image)"
    say "Capture $CAPTURE terminée : $CAPTURE.txt et $CAPTURE.raw dans $DIR"
    CAPTURE=""
    LLDB_PID=""
}

stop_guide() {  # on Ctrl-C or end of input
    say ""
    if [ "$DRY_RUN" = 1 ] && [ -n "$LLDB_PID" ]; then
        kill "$LLDB_PID" 2>/dev/null   # the placeholder only; a real FlexColor is left to the user
        LLDB_PID=""
    fi
    if capture_alive; then
        say "Arrêt du guide. FlexColor tourne encore sous lldb (capture $CAPTURE) :"
        say "quittez FlexColor normalement ; lldb s'arrêtera avec lui et le journal sera complet."
        state "allumé" "à quitter"
        note "guide arrêté pendant la capture $CAPTURE"
    else
        say "Arrêt du guide."
        state "allumé (à éteindre en fin de session, C4)" "fermé"
        note "guide arrêté"
    fi
    say "Pour reprendre : --from $CURRENT_STEP (même dossier, X1GUIDE_DIR si un autre jour)."
    exit "${1:-130}"
}
trap 'stop_guide 130' INT

# ---------------------------------------------------------------------------
# Screenshots: every on-screen FlexColor window (the frame values may be in a
# palette), and the whole screen.

flexcolor_window_ids() {
    /usr/bin/python - <<'PY' 2>/dev/null
import Quartz
windows = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID)
for w in windows:
    b = w.get('kCGWindowBounds', {})
    if w.get('kCGWindowOwnerName') == 'FlexColor' and b.get('Width', 0) > 40 and b.get('Height', 0) > 40:
        print(w.get('kCGWindowNumber'))
PY
}

screenshot() {  # screenshot STEP LABEL
    local base id n=0
    base="$DIR/ecran-$(printf '%02d' "$1")-$2-$(date +%H%M%S)"
    if [ "$DRY_RUN" = 1 ]; then
        : > "$base-ecran.png"
    else
        screencapture -x "$base-ecran.png"
        for id in $(flexcolor_window_ids); do
            n=$((n + 1))
            screencapture -x -o -l "$id" "$base-fenetre$n.png"
        done
    fi
    note "étape $1 : captures d'écran $(basename "$base")-* (écran entier et $n fenêtre(s) FlexColor)"
}

# ---------------------------------------------------------------------------
# Steps (docs/test-session.md, part G)

ensure_essai_i() {  # steps 2-13: FlexColor must still run under lldb, else a new run with its preview
    if capture_alive; then return; fi
    if [ -n "$CAPTURE" ]; then
        say ""
        say "ATTENTION : FlexColor ou lldb s'est arrêté (capture $CAPTURE)."
        end_capture
    fi
    state "allumé" "fermé, puis relancé par le guide"
    say "Porte-film 6×7 avec le même film qu'avant : vérifiez qu'il est en place."
    wait_enter "Entrée quand le porte-film 6×7 est en place."
    note "étape $CURRENT_STEP : reprise, porte-film 6×7 en place"
    start_capture essai-I
    say "Reprise : FlexColor vient d'être relancé. Faites d'abord un aperçu."
    wait_enter "Entrée quand l'aperçu est fini."
    note "étape $CURRENT_STEP : aperçu de reprise fait"
    screenshot "$CURRENT_STEP" apercu-reprise
}

ensure_essai_l() {  # steps 24-31: FlexColor must still run under lldb, else a new run with its preview
    if capture_alive; then return; fi
    if [ -n "$CAPTURE" ]; then
        say ""
        say "ATTENTION : FlexColor ou lldb s'est arrêté (capture $CAPTURE)."
        end_capture
    fi
    state "allumé" "fermé, puis relancé par le guide"
    say "Porte-film 6×7 avec la mire IT8, comme à l'étape 23 : vérifiez qu'il est en place."
    wait_enter "Entrée quand le porte-film 6×7 est en place."
    note "étape $CURRENT_STEP : reprise, porte-film 6×7 en place"
    start_capture essai-L
    say "Reprise : FlexColor vient d'être relancé. Faites d'abord un aperçu."
    wait_enter "Entrée quand l'aperçu est fini."
    note "étape $CURRENT_STEP : aperçu de reprise fait"
    screenshot "$CURRENT_STEP" apercu-reprise
    say "Le cadre P0 est perdu : faites un nouveau cadre 0,50 × 0,50 cm au centre ;"
    say "les étapes suivantes partent de ce nouveau cadre."
    note "étape $CURRENT_STEP : nouveau cadre P0"
    if [ "$CURRENT_STEP" -ge 25 ] && [ "$CURRENT_STEP" -le 26 ]; then
        # Steps 25-26 compare P0 at three line pitches: the new P0 needs its 2 000 ppi scan first.
        say "Refaites d'abord l'étape 24 avec ce nouveau cadre : 2 000 ppi, cliquez sur Scan."
        wait_enter "Entrée quand le TIFF est enregistré."
        note "étape 24 (refaite à la reprise) : scan fait (2000 ppi, nouveau cadre P0)"
        frame_size 24
        screenshot 24 scan-2000ppi-reprise
    fi
}

frame_size() {  # frame_size STEP: notes the frame size FlexColor shows, as typed
    local size
    if [ -t 0 ]; then
        while read -r -t 1 _; do :; done
    fi
    printf '%s ' "Largeur × hauteur affichées par FlexColor (ex. 0,50 × 0,51 ; Entrée si illisible) :"
    if ! read -r size; then
        say ""
        say "Entrée standard fermée : arrêt du guide."
        stop_guide 1
    fi
    note "étape $1 : cadre affiché ${size:-non noté}"
}

holder_size() {  # holder_size STEP: reference and opening in mm and inches (holders.json)
    case $1 in
        1)  echo "réf. 50200403, ouverture 57 × 70 mm (2¼″ × 2,76″)" ;;
        15) echo "réf. 50200428, ouvertures 57 × 57 / 57 × 42,5 mm (2¼″ × 2¼″ / 2¼″ × 1⅔″)" ;;
        16) echo "réf. 50200404, deux vues de 57 × 57 mm (2¼″ × 2¼″)" ;;
        17) echo "réf. 50200401, ouverture 24 × 35 mm (0,94″ × 1,38″)" ;;
        18) echo "réf. 50200402, ouverture 94 × 119 mm (3,70″ × 4,69″)" ;;
        19) echo "réf. 50200416, six vues, ouverture 24 × 226 mm (0,94″ × 8,9″)" ;;
        20) echo "réf. 50200405, ouverture 57 × 90 mm (2¼″ × 3,54″)" ;;
        21) echo "réf. 50200411, quatre vues, ouverture 24 × 149 mm (0,94″ × 5,87″)" ;;
    esac
}

do_step() {  # do_step STEP: shows the step, waits, notes, screenshots
    local s=$1 res="" frame=""
    if [ "$s" -gt "$PART_G_LAST" ]; then do_part_h "$s"; return; fi
    case $s in
        1)
            banner "Étape 1/22 : aperçu (porte-film 6×7, capture essai-I)"
            state "allumé" "fermé, puis lancé par le guide"
            say "Porte-film 6×7 avec le même film qu'avant : insérez-le."
            say "  $(holder_size 1)"
            wait_enter "Entrée quand le porte-film 6×7 est en place."
            note "étape 1 : porte-film 6×7 en place"
            [ -z "$CAPTURE" ] || end_capture
            start_capture essai-I
            say "Dans FlexColor : cliquez sur Aperçu (Prescan) et attendez la fin."
            wait_enter "Entrée quand l'aperçu est fini."
            note "étape 1 : aperçu fait"
            if ask_yes "Le X1 venait-il d'être allumé, sans aperçu depuis (aperçu à froid) ?"; then
                note "étape 1 : aperçu à froid (X1 allumé sans aperçu avant)"
            else
                note "étape 1 : aperçu après un autre depuis la mise sous tension"
            fi
            screenshot 1 apercu
            return ;;
        2) res=600 ;; 3) res=1000 ;; 4) res=1500 ;; 5) res=2000 ;; 6) res=2500 ;; 7) res=3200 ;;
        8) res=2000; frame="1,0 × 1,0 cm, à environ 5 mm du bord GAUCHE de l'ouverture" ;;
        9) res=2000; frame="1,0 × 1,0 cm, à environ 5 mm du bord DROIT de l'ouverture" ;;
        10) res=2000; frame="1,0 × 1,0 cm, à environ 5 mm du HAUT de l'ouverture" ;;
        11) res=2000; frame="1,0 × 1,0 cm, à environ 5 mm du BAS de l'ouverture" ;;
        12) res=2000; frame="3,0 × 1,0 cm (large), centré" ;;
        13) res=2000; frame="1,0 × 3,0 cm (haut), centré" ;;
    esac
    if [ "$s" -ge 2 ] && [ "$s" -le 13 ]; then
        [ -n "$frame" ] || frame="1,0 × 1,0 cm au centre de l'ouverture"
        banner "Étape $s/22 : scan (porte-film 6×7, capture essai-I)"
        ensure_essai_i
        state "allumé" "ouvert sous lldb (capture en cours)"
        say "Cadre : $frame."
        say "Résolution : $res ppi. Pas de nouvel aperçu."
        say "Les captures d'écran gardent ce que FlexColor affiche (X, Y, largeur, hauteur)."
        say "Cliquez sur Scan et attendez la fin de l'enregistrement du TIFF."
        wait_enter "Entrée quand le TIFF est enregistré."
        note "étape $s : scan fait ($res ppi, $frame)"
        screenshot "$s" "scan-${res}ppi"
        return
    fi
    if [ "$s" = 14 ]; then
        banner "Étape 14/22 : fin de la capture essai-I"
        state "allumé" "à quitter"
        if [ -n "$CAPTURE" ]; then end_capture; else say "Aucune capture en cours."; fi
        note "étape 14 : fin"
        return
    fi
    if [ "$s" -ge 15 ] && [ "$s" -le 21 ]; then
        local holder size name scan=0
        case $s in
            15) holder="6×6 / 6×4,5"; size="$(holder_size 15)"; name=essai-J1 ;;
            16) holder="6×6×2"; size="$(holder_size 16)"; name=essai-J2 ;;
            17) holder="24×36"; size="$(holder_size 17)"; name=essai-J3; scan=1 ;;
            18) holder="4×5"; size="$(holder_size 18)"; name=essai-J4; scan=1 ;;
            19) holder="24×36×6"; size="$(holder_size 19)"; name=essai-J5 ;;
            20) holder="6×9"; size="$(holder_size 20)"; name=essai-J6 ;;
            21) holder="24×36×4"; size="$(holder_size 21)"; name=essai-J7 ;;
        esac
        banner "Étape $s/22 : premier aperçu du porte-film $holder (capture $name)"
        [ -z "$CAPTURE" ] || end_capture
        state "allumé" "fermé, puis lancé par le guide"
        say "Changez de porte-film : $holder."
        say "  $size"
        if [ "$s" = 17 ]; then
            say "  Le 24×36 à UNE seule vue, étiqueté « 24x35 / 35x24 » (FlexColor affiche"
            say "  « 24x36 / 36x24 ») : pas le 24×36×4 ni le 24×36×6 (bandes de vues)."
        fi
        say "Notez la référence imprimée dessus."
        wait_enter "Entrée quand le porte-film $holder est en place."
        note "étape $s : porte-film $holder en place"
        start_capture "$name"
        say "Dans FlexColor : cliquez sur Aperçu. Ne touchez pas au menu Format."
        say "Notez le format affiché par FlexColor."
        wait_enter "Entrée quand l'aperçu est fini."
        note "étape $s : aperçu fait"
        screenshot "$s" apercu
        if [ "$scan" = 1 ]; then
            say ""
            say "Puis : cadre 1,0 × 1,0 cm centré, 1 000 ppi, cliquez sur Scan."
            wait_enter "Entrée quand le TIFF est enregistré."
            note "étape $s : scan 1 000 ppi fait"
            screenshot "$s" scan-1000ppi
        fi
        state "allumé" "à quitter"
        end_capture
        return
    fi
    if [ "$s" = 22 ]; then
        banner "Étape 22/22 (facultative) : démarrage à froid (capture essai-K)"
        [ -z "$CAPTURE" ] || end_capture
        if ! ask_yes "Faire cette étape facultative ?"; then
            note "étape 22 : sautée"
            return
        fi
        state "à éteindre" "fermé"
        say "Notez quel porte-film a servi en dernier dans FlexColor (normalement le 24×36×4)."
        say "Éteignez le X1."
        wait_enter "Entrée quand le X1 est éteint."
        note "étape 22 : X1 éteint"
        state "à rallumer" "fermé"
        say "Rallumez le X1 et attendez qu'il soit prêt, puis insérez le porte-film 6×7."
        wait_enter "Entrée quand le X1 est prêt et le porte-film 6×7 en place."
        note "étape 22 : X1 rallumé, porte-film 6×7 en place"
        start_capture essai-K
        say "Dans FlexColor : cliquez sur Aperçu."
        wait_enter "Entrée quand l'aperçu est fini."
        note "étape 22 : aperçu fait"
        screenshot 22 apercu
        state "allumé" "à quitter"
        end_capture
        return
    fi
}

# Part H (docs/test-session.md): offset 62 of the 400-line window. One run
# (essai-L), 6×7 holder: one 0.50 × 0.50 cm frame left untouched at 2 000,
# 600 and 3 200 ppi, then moved by FlexColor's smallest steps along the
# drum, then two other heights.
do_part_h() {  # do_part_h STEP
    local s=$1 res=2000 frame=""
    case $s in
        23)
            banner "Étape 23/32 : aperçu (porte-film 6×7, mire IT8, capture essai-L)"
            state "allumé" "fermé, puis lancé par le guide"
            say "Porte-film 6×7 avec la mire IT8, dans le même sens que pour essai-I."
            say "  $(holder_size 1)"
            wait_enter "Entrée quand le porte-film 6×7 est en place."
            note "étape 23 : porte-film 6×7 en place"
            [ -z "$CAPTURE" ] || end_capture
            start_capture essai-L
            say "Dans FlexColor : cliquez sur Aperçu et attendez la fin."
            wait_enter "Entrée quand l'aperçu est fini."
            note "étape 23 : aperçu fait"
            if ask_yes "Le X1 venait-il d'être allumé, sans aperçu depuis (aperçu à froid) ?"; then
                note "étape 23 : aperçu à froid (X1 allumé sans aperçu avant)"
            else
                note "étape 23 : aperçu après un autre depuis la mise sous tension"
            fi
            screenshot 23 apercu
            return ;;
        24) frame="0,50 × 0,50 cm au centre de l'ouverture (cadre P0)" ;;
        25) res=600; frame="le même cadre P0, SANS LE TOUCHER" ;;
        26) res=3200; frame="le même cadre P0, SANS LE TOUCHER" ;;
        27) frame="le même, descendu du plus petit pas possible (P0 + 1 pas)" ;;
        28) frame="le même, descendu encore d'un pas (P0 + 2 pas)" ;;
        29) frame="le même, descendu encore d'un pas (P0 + 3 pas)" ;;
        30) frame="sans le déplacer, hauteur 0,51 cm (largeur 0,50)" ;;
        31) frame="sans le déplacer, hauteur 0,52 cm (largeur 0,50)" ;;
        32)
            banner "Étape 32/32 : fin de la capture essai-L"
            state "allumé" "à quitter"
            if [ -n "$CAPTURE" ]; then end_capture; else say "Aucune capture en cours."; fi
            note "étape 32 : fin"
            return ;;
    esac
    banner "Étape $s/32 : scan (porte-film 6×7, capture essai-L)"
    ensure_essai_l
    state "allumé" "ouvert sous lldb (capture en cours)"
    say "Cadre : $frame."
    say "Résolution : $res ppi. Pas de nouvel aperçu."
    if [ "$s" -ge 25 ] && [ "$s" -le 26 ]; then
        say "Ne touchez pas au cadre : seule la résolution change (champ PPP de FlexColor)."
    fi
    if [ "$s" -ge 27 ] && [ "$s" -le 29 ]; then
        say "Un pas : la flèche ↓ si FlexColor déplace le cadre au clavier, sinon"
        say "un glissement le plus court possible. Chaque position donne une autre"
        say "fraction de ligne ; leur valeur exacte n'est pas connue, il en faut seulement plusieurs."
    fi
    say "Cliquez sur Scan et attendez la fin de l'enregistrement du TIFF."
    wait_enter "Entrée quand le TIFF est enregistré."
    note "étape $s : scan fait ($res ppi, $frame)"
    frame_size "$s"
    screenshot "$s" "scan-${res}ppi"
}

list_steps() {
    say "Étapes (docs/test-session.md, partie G) :"
    say "  1      essai-I : lancer FlexColor, aperçu (6×7)"
    say "  2-7    essai-I : cadre 1 × 1 cm centré, 600 / 1 000 / 1 500 / 2 000 / 2 500 / 3 200 ppi"
    say "  8-11   essai-I : 1 × 1 cm à 2 000 ppi, bord gauche / droit / haut / bas"
    say "  12-13  essai-I : 3 × 1 cm puis 1 × 3 cm centrés, 2 000 ppi"
    say "  14     essai-I : quitter FlexColor"
    say "  15-21  essai-J1 à J7 : un aperçu par porte-film (+ un scan 1 000 ppi en 17 et 18)"
    say "  22     essai-K (facultatif) : X1 éteint puis rallumé, aperçu 6×7"
    say ""
    say "Partie H (offset 62 de la mise au point ; --part H ou --from 23) :"
    say "  23     essai-L : lancer FlexColor, aperçu (6×7, mire IT8)"
    say "  24-26  essai-L : cadre 0,50 × 0,50 cm centré (P0), 2 000 puis 600 et 3 200 ppi sans le toucher"
    say "  27-29  essai-L : le même, descendu de 1, 2, 3 petits pas, 2 000 ppi"
    say "  30-31  essai-L : sans le déplacer, hauteur 0,51 puis 0,52 cm, 2 000 ppi"
    say "  32     essai-L : quitter FlexColor"
}

# ---------------------------------------------------------------------------

FROM=1
FROM_GIVEN=""
PART_GIVEN=""
while [ $# -gt 0 ]; do
    case $1 in
        --from)
            [ $# -ge 2 ] || { say "--from attend un numéro d'étape (1 à $LAST_STEP)"; exit 2; }
            FROM=$2; FROM_GIVEN=1; shift 2 ;;
        --part)
            [ $# -ge 2 ] || { say "--part attend G ou H"; exit 2; }
            case $2 in G|g) FROM=1 ;; H|h) FROM=$((PART_G_LAST + 1)) ;; *) say "--part attend G ou H"; exit 2 ;; esac
            PART_GIVEN=1; shift 2 ;;
        --list) list_steps; exit 0 ;;
        -h|--help) sed -n '3,34p' "$0"; exit 0 ;;
        *) say "Option inconnue : $1 (voir --help)"; exit 2 ;;
    esac
done
if [ -n "$FROM_GIVEN" ] && [ -n "$PART_GIVEN" ]; then
    say "--part et --from ne vont pas ensemble : --from choisit déjà la partie de son étape."
    exit 2
fi
case $FROM in
    ''|*[!0-9]*) say "--from attend un numéro d'étape (1 à $LAST_STEP)"; exit 2 ;;
esac
FROM=$((10#$FROM))   # "08" is step 8, not an octal number
if [ "$FROM" -lt 1 ] || [ "$FROM" -gt "$LAST_STEP" ]; then
    say "--from attend un numéro d'étape (1 à $LAST_STEP)"; exit 2
fi

if [ "$DRY_RUN" != 1 ]; then
    [ -x "$FLEXCOLOR" ] || { say "FlexColor introuvable : $FLEXCOLOR (X1GUIDE_FLEXCOLOR)"; exit 1; }
    [ -f "$CAP3" ] || { say "cap3.py introuvable : $CAP3 (X1GUIDE_CAP3)"; exit 1; }
    [ "$(basename "$CAP3")" = cap3.py ] || { say "Le fichier doit s'appeler cap3.py (ses rappels sont cap3.*) : $CAP3"; exit 1; }
    command -v lldb >/dev/null 2>&1 || { say "lldb introuvable (outils de ligne de commande Xcode)"; exit 1; }
    lldb --help 2>/dev/null | grep -q -- '--batch' || {
        say "Ce lldb n'a pas l'option --batch : faites les captures à la main (docs/test-session.md, C2)."
        exit 1
    }
fi
mkdir -p "$DIR" || exit 1

banner "Session de captures guidée — dossier : $DIR"
if [ "$FROM" -le "$PART_G_LAST" ]; then PART=G; else PART=H; fi
# The first preview of this run: a resume preview in the middle of a capture
# (essai-I: 2-13, essai-L: 24-31), the next step after a step that only quits.
case $FROM in
    [2-9]|1[0-3]|2[4-9]|3[01]) FIRST_PREVIEW="$FROM (aperçu de reprise)" ;;
    14) FIRST_PREVIEW=15 ;;
    *) FIRST_PREVIEW=$FROM ;;
esac
say "Avant de commencer (docs/test-session.md, C1 et partie $PART) :"
state "allumé, branché sur ce Mac" "fermé"
case $FROM in
    22) say "L'étape 22 fait exprès un aperçu à froid (X1 éteint puis rallumé)." ;;
    32) ;;
    *)
        say "Le X1 doit avoir fait au moins un aperçu depuis sa mise sous tension ;"
        say "sinon l'aperçu de l'étape $FIRST_PREVIEW sera un aperçu à froid (à noter)." ;;
esac
say "Pour chaque scan, FlexColor enregistre son TIFF : gardez-le, hors du dépôt."
say "Vérifiez qu'aucun numéro de série ni nom de client n'apparaît sur les captures d'écran."
say "Le guide ne parle jamais au X1 : seul FlexColor le fait."
note "guide démarré à l'étape $FROM (dossier $DIR)"
wait_enter "Entrée pour commencer à l'étape $FROM."

# A run stays within the part of its first step.
if [ "$FROM" -le "$PART_G_LAST" ]; then END_STEP=$PART_G_LAST; else END_STEP=$LAST_STEP; fi
step=$FROM
while [ "$step" -le "$END_STEP" ]; do
    CURRENT_STEP=$step
    do_step "$step"
    step=$((step + 1))
done
[ -z "$CAPTURE" ] || end_capture
note "session terminée"
banner "Session terminée. Tout est dans $DIR"
say "Pour finir (docs/test-session.md, C4) :"
state "à éteindre" "fermé"
say "Éteignez le X1. Copiez le dossier vers ~/X1-captures/<date>/ (hors du dépôt)."
