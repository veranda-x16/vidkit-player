; VIDKIT Player: a video and audio player for Veranda, in Prog8.
;
; Plays SPV videos (the X16 Movie Maker's) and WAV / ZCM audio from the SD
; card with VIDKIT. Its window follows Veranda's MOD Player (veranda-x16/
; mod-player, examples/veranda: MIT licence), whose layout, look and
; pictures it ports: a playlist of the folder, "Now playing", the transport
; buttons with their lights, a progress bar, a status bar, and in the
; bottom panel a deck with an audio CD that turns while audio plays.
;
; How playing works (lib/vkx.p8): VIDKIT plays in the foreground, so each
; play is an "excursion" that parks Veranda and brings it back. A video
; takes the whole screen (Veranda fades out, then in again, and the window
; is drawn anew); audio plays in the window, the deck's disc and the
; progress bar drawn by VIDKIT's frame driver, the buttons still working
; (the mouse is followed by the control routine).
;
; Every action that plays something is done from the main loop (appMain),
; not from inside a menu's or an icon's routine: a video redraws the whole
; screen, menus and icons included.
;
; Room: some locals are aliases of the zero-page registers (cx16.r5-r10),
; which saves bytes below $8800. Only where nothing in the variable's span
; writes that register: no Veranda call (the kernel uses r0-r15 freely),
; and only calls whose code was checked (Prog8's own library uses r0-r2
; and r12-r15; lower(), rank(), slot() none). A sub holding an alias across
; a call uses other registers than the sub it calls (list_sort r8/r9 around
; ent_cmp's r5/r6). play_control runs inside VIDKIT, which vkx.user_call
; shields (r0-r15 kept around the call).

%import vr
%import vrkit
%import vrlook
%import vkx
%import vktape
%import conv
%import strings

main {
    ; ---------------------------------------------------------------- layout (the MOD Player's)
    const ubyte WIN_X = 1
    const ubyte WIN_Y = 3
    const ubyte WIN_W = 78
    const ubyte WIN_H = 56
    const uword WIN_L = 8
    const uword STAT_LINE = 456
    const uword STAT_SPLIT = 360        ; the left text clears up to here (the modes are on the right)

    const uword LP_L = 15          ; the playlist panel
    const uword LP_T = 47
    const uword LP_R = 336
    const uword LP_B = 328
    const ubyte LIST_COL = 2
    const uword LIST_X = 16
    const uword LIST_XR = 326
    const uword LIST_Y = 64
    const uword ROW_H = 16
    const ubyte LIST_N = 16
    const ubyte SB_COL = 41
    const ubyte SB_ROW0 = 8
    const ubyte SB_ROWN = 39
    const ubyte SB_TRACK = 30

    const uword RP_L = 343         ; now playing
    const uword RP_T = 47
    const uword RP_R = 624
    const uword RP_B = 328
    const uword RP_X = 352
    const ubyte PROG_COL = 44
    const ubyte PROG_W = 33
    const ubyte PROG_ROW = 22
    const ubyte ICON_Y = 192
    const ubyte ICON_COL0 = 48
    const ubyte LED_ROW = 28

    const uword VP_L = 15          ; the deck
    const uword VP_T = 343
    const uword VP_R = 624
    const uword VP_B = 440
    const uword DISC_X = 288       ; the disc, 64 x 64 (x on a card)
    const uword DISC_Y = 368
    const uword LG_X1 = 28         ; the key legend: left of the disc (under its header),
    const uword LG_X2 = 456        ; right of it, nearer the panel's edge
    const uword LG_Y = 373         ; the header's baseline; the keys' lines follow
    const uword LG_DY = 15
    const uword LG_KEYW = 64       ; the key names' column: left,
    const uword LG_KEYW2 = 32      ; right (F5, Tab: short)

    ; ---------------------------------------------------------------- the folder's entries
    ; in two RAM banks, 64 bytes each: the type, the name. Types: U "..",
    ; D a folder, V a video (SPV), A audio (WAV, ZCM), L a name too long
    const ubyte ENT_MAX = 255
    ubyte ent_bank
    ubyte n_ent
    ubyte n_media
    ubyte top
    ubyte sel
    ubyte[ENT_MAX] order
    ubyte[64] cur
    ubyte[67] dirent                ; DirNext's: 'D' or 'F', the size, the name
    ubyte[64] tmpname

    ; ---------------------------------------------------------------- state
    ubyte playing_ent = $FF
    bool  repeat_on
    bool  next_on                   ; "Play next": after a file finishes, the next one (off at the start)
    bool  shuffle
    ubyte pending = 0               ; an action for the main loop:
    const ubyte P_NONE = 0
    const ubyte P_PLAY = 1          ;   play pending_ent
    const ubyte P_STEP = 2          ;   the next (pending_dir 1) or previous (-1) one
    ubyte pending_ent
    byte  pending_dir
    byte  step_after                ; set during play: next/previous asked for (a button)
    ubyte track_no
    ubyte[16] hist                  ; the shuffle's history
    ubyte n_hist
    ubyte last_buttons
    bool  leds_paused

    ; the media's header (media_info)
    const ubyte K_NONE = 0
    const ubyte K_VIDEO = 1
    const ubyte K_WAV = 2
    const ubyte K_ZCM = 3
    ubyte m_kind
    ubyte m_vtype
    ubyte m_bpp
    ubyte m_fps
    uword m_w
    uword m_h
    long  m_frames
    bool  m_spi
    bool  m_stereo
    bool  m_16bit
    long  m_hz
    long  m_bytes                   ; audio: the PCM data's size
    long  m_rate                    ; audio: bytes a second
    uword m_secs                    ; its length in seconds
    ubyte[48] hdr

    ; ---------------------------------------------------------------- menus
    const ubyte IH = 16
    ubyte[vrkit.MENU_HDR + 1 * vrkit.MENU_ITEM] m_app
    ubyte[vrkit.MENU_HDR + 2 * vrkit.MENU_ITEM] m_file
    ubyte[vrkit.MENU_HDR + 7 * vrkit.MENU_ITEM] m_play
    ubyte[vrkit.MENU_HDR + 3 * vrkit.MENU_ITEM] m_bar
    str T_APP = "VIDKIT Player"
    str T_FILE = "File"
    str T_PLAY = "Play"
    str T_REPEAT0 = "Repeat: off"
    str T_REPEAT1 = "Repeat: on"
    str T_SHUFFLE0 = "Shuffle: off"
    str T_SHUFFLE1 = "Shuffle: on"
    str T_NEXT0 = "Play next: off"
    str T_NEXT1 = "Play next: on"
    uword[3] @nosplit bar_names = [&T_APP, &T_FILE, &T_PLAY]

    ; ---------------------------------------------------------------- the transport buttons (DoIcons)
    ubyte[4 + 5 * 8] icons

    sub start() {
        boxes()
        vr.longNames = vr.LONG_NAMES
        ent_bank = vr.BankAlloc(2)
        if ent_bank == 0 or not vkx.setup() {
            void vr.DoDlgBox(&box_nomem)
            sys.exit(0)
        }
        vkx.redraw = &redraw_all
        vkx.control = &play_control
        vkx.frame_driver = &vktape.driver
        ; the deck's disc (overlay record 4, tools/mkdisc.py) and the progress bar (the colour map) for vktape
        void vr.LoadOverlay(4, 0)
        vktape.disc_load(cx16.r1L)
        vktape.disc_x = DISC_X
        vktape.disc_y = DISC_Y
        vktape.bar_style = vktape.BAR_MAP
        vktape.bar_x = PROG_COL
        vktape.bar_w = PROG_W
        vktape.bar_row = PROG_ROW
        vktape.bar_colour = vrlook.SELECT
        if vr.curDirName[0] == 0 {
            vr.curDirName[0] = '/'
            vr.curDirName[1] = 0
        }
        void vr.ChDir(&vr.curDirName)
        list_read()
        draw_all()
        ui_status("Stopped")
        if not AUTOTEST
            vr.otherPressVec = &pressed     ; (the test build takes no clicks: it plays by itself, in the room this leaves)
        vr.keyVector = &key
        vr.appMain = &update
        vr.LogText("VIDPLAYER RUNNING")
    }

    ; ================================================================= the window

    sub draw_all() {
        frame()
        labels()
        status_modes()
        if not AUTOTEST
            icons_on()                      ; (the test build takes no clicks: room for its checks)
        panel()
        ui_track()
        menus()
    }

    sub redraw_all() {
        ; after a video (vkx: the palette still black, both screens cleared, then
        ; one fade in to vkx.pal_veranda): the theme's colours go there, not to
        ; VERA - written straight away they lit the half-drawn window before the
        ; fade (the "double step")
        vrlook.pal_to = vkx.pal_veranda
        draw_all()
        vrlook.pal_to = 0
    }

    sub frame() {
        vrlook.theme_load()
        vrlook.theme_palette()
        vr.dispBufferOn = vr.ST_WR_FORE | vr.ST_WR_BACK
        vr.ColorRect(0, 80, 2, 58, vrlook.desk)
        if vrlook.desk != 0
            vr.SetPattern(0)
        else
            vr.SetPattern(2)
        vr.WRectangle(0, 16, 639, 479)
        vrlook.win_set(WIN_X, WIN_Y, WIN_W, WIN_H, 0, 2, vrlook.VW_CLOSE | vrlook.VW_FRAME | vrlook.VW_SHADOW)
        vrlook.win("VIDKIT Player")
        ; the panels
        vr.WFrameRectangle($ff, LP_L, LP_T, LP_R, LP_B)
        vr.ColorRect(2, 40, 6, 2, vrlook.CHROME)
        vr.WHorizontalLine($ff, LP_L, LP_R, 63)
        vr.WFrameRectangle($ff, RP_L, RP_T, RP_R, RP_B)
        vr.ColorRect(43, 35, 6, 2, vrlook.CHROME)
        vr.WHorizontalLine($ff, RP_L, RP_R, 63)
        vr.currentMode = vr.SET_BOLD
        vr.WPutString("Now playing", RP_X, 59)
        vr.currentMode = 0
        ; the deck
        vr.WFrameRectangle($ff, VP_L, VP_T, VP_R, VP_B)
        vr.ColorRect(2, 76, 43, 2, vrlook.CHROME)
        vr.WHorizontalLine($ff, VP_L, VP_R, VP_T + 16)
        vr.currentMode = vr.SET_BOLD
        vr.WPutString("Deck", LIST_X + 6, VP_T + 12)
        vr.currentMode = 0
        if not AUTOTEST
            legend()                        ; (not in the test build: room for its checks)
        vktape.reset()
        vktape.disc_idle()
    }

    ; the keys while a file plays (VIDKIT's key controller, and Tab: the
    ; player's skip in a list): pairs of key and what it does, three a column,
    ; either side of the disc
    str[] @nosplit legend_text = ["Esc", "stop", "Space", "pause", "Up/Down", "volume",
                        "F5", "play again at end", "Tab", "next file in a list"]

    sub legend() {
        vr.currentMode = vr.SET_BOLD | vr.SET_UNDERLINE
        vr.WPutString("Keys during play", LG_X1, LG_Y)
        ubyte k
        for k in 0 to 4 {
            uword x = LG_X1
            uword kw = LG_KEYW
            ubyte row = k + 1
            if k >= 3 {
                x = LG_X2
                kw = LG_KEYW2
                row = k - 2
            }
            uword y = LG_Y + (row as uword) * LG_DY
            vr.currentMode = vr.SET_BOLD
            vr.WPutString(legend_text[k * 2], x, y)
            vr.currentMode = 0
            vr.WPutString(legend_text[k * 2 + 1], x + kw, y)
        }
    }

    ; ---------------------------------------------------------------- the menus

    sub menus() {
        ; Veranda Look 2's menus: the first named after the program, lists under their bar items
        uword e0 = vrlook.bar_end(&bar_names, 0)
        uword e1 = vrlook.bar_end(&bar_names, 1)
        uword e2 = vrlook.bar_end(&bar_names, 2)
        uword e3 = vrlook.bar_end(&bar_names, 3)
        vrkit.menu(m_app, 16, 16 + IH, e0, e0 + vrlook.text_w_ui("About VIDKIT Player") + 16, vr.VERTICAL)
        vrkit.item("About VIDKIT Player", vr.MENU_ACTION, &m_about)
        vrkit.menu(m_file, 16, 16 + 2 * IH, e1, e1 + vrlook.text_w_ui("Play all") + 24, vr.VERTICAL)
        vrkit.item("Play all", vr.MENU_ACTION, &m_playall)
        vrkit.item("Quit", vr.MENU_ACTION, &m_quit)
        vrkit.menu(m_play, 16, 16 + 7 * IH, e2, e2 + vrlook.text_w_ui(T_NEXT0) + 16, vr.VERTICAL)
        vrkit.item("Play", vr.MENU_ACTION, &m_playmenu)
        vrkit.item("Stop", vr.MENU_ACTION, &m_stop)
        vrkit.item("Next", vr.MENU_ACTION, &m_next)
        vrkit.item("Previous", vr.MENU_ACTION, &m_prev)
        vrkit.item(T_REPEAT0, vr.MENU_ACTION, &m_repeat)
        vrkit.item(T_SHUFFLE0, vr.MENU_ACTION, &m_shuffle)
        vrkit.item(T_NEXT0, vr.MENU_ACTION, &m_next_on)
        menu_marks()
        vrkit.menu(m_bar, 0, 14, 0, e3, vr.HORIZONTAL | vr.UN_CONSTRAINED)
        vrkit.item(T_APP, vr.SUB_MENU, &m_app)
        vrkit.item(T_FILE, vr.SUB_MENU, &m_file)
        vrkit.item(T_PLAY, vr.SUB_MENU, &m_play)
        vrlook.theme_menus()
        vr.DoMenu(&m_bar, 0)
    }

    sub menu_marks() {
        ; the items' texts: (the item's text address is its first word)
        if repeat_on
            pokew(&m_play + vrkit.MENU_HDR + 4 * vrkit.MENU_ITEM, &T_REPEAT1)
        else
            pokew(&m_play + vrkit.MENU_HDR + 4 * vrkit.MENU_ITEM, &T_REPEAT0)
        if shuffle
            pokew(&m_play + vrkit.MENU_HDR + 5 * vrkit.MENU_ITEM, &T_SHUFFLE1)
        else
            pokew(&m_play + vrkit.MENU_HDR + 5 * vrkit.MENU_ITEM, &T_SHUFFLE0)
        if next_on
            pokew(&m_play + vrkit.MENU_HDR + 6 * vrkit.MENU_ITEM, &T_NEXT1)
        else
            pokew(&m_play + vrkit.MENU_HDR + 6 * vrkit.MENU_ITEM, &T_NEXT0)
    }

    sub m_about() {
        vr.GotoFirstMenu()
        void vr.DoDlgBox(&box_about)
        void take_wheel()                   ; (turns made meanwhile don't scroll)
    }
    sub m_playall() {
        ; the folder's first file, then on (a run: bookmarks used, not asked).
        ; An empty folder: nothing (a for loop to n_ent - 1 went through 256
        ; stale entries there: 0 - 1 is 255 for a ubyte)
        vr.GotoFirstMenu()
        ubyte e = 0
        while e < n_ent {
            ent_get(e)
            if cur[0] == 'V' or cur[0] == 'A' {
                quiet_once = true
                ask_play(e)
                return
            }
            e++
        }
    }
    sub m_quit() {
        vr.GotoFirstMenu()
        quit()
    }
    sub quit() {
        blank_release()                     ; (Veranda's blanking as it was)
        sys.exit(0)
    }
    sub m_playmenu() {
        vr.GotoFirstMenu()
        play_selected()
    }
    sub m_stop() {
        vr.GotoFirstMenu()           ; (nothing plays now: play returns when it stops)
    }
    sub m_next() {
        vr.GotoFirstMenu()
        ask_step(1)
    }
    sub m_prev() {
        vr.GotoFirstMenu()
        ask_step(-1)
    }
    sub m_repeat() {
        vr.GotoFirstMenu()
        repeat_on = not repeat_on
        menu_marks()
        status_modes()
    }
    sub m_next_on() {
        vr.GotoFirstMenu()
        next_on = not next_on
        menu_marks()
        status_modes()
    }
    sub m_shuffle() {
        vr.GotoFirstMenu()
        shuffle = not shuffle
        n_hist = 0
        menu_marks()
        status_modes()
    }

    ; the dialog boxes: a position byte, then commands; the strings' addresses in words
    ubyte[] box_about = [vr.DEF_DB_POS | 1,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_1_Y, 0, 0,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_2_Y, 0, 0,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_3_Y, 0, 0,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_4_Y, 0, 0,
        vr.OK, vr.DBI_X_2, vr.DBI_Y_2,
        0]
    ubyte[] box_nomem = [vr.DEF_DB_POS | 1,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_2_Y, 0, 0,
        vr.OK, vr.DBI_X_2, vr.DBI_Y_2,
        0]
    str A1 = "VIDKIT Player 1.0"
    ; (the standard box shows about 24 characters a line)
    str A2 = "SPV video, WAV and ZCM"
    str A3 = "audio via VIDKIT,"
    str A4 = "by Anthony W. Henry"
    str N1 = "Not enough RAM banks."

    sub boxes() {
        pokew(&box_about + 4, &A1)
        pokew(&box_about + 9, &A2)
        pokew(&box_about + 14, &A3)
        pokew(&box_about + 19, &A4)
        pokew(&box_nomem + 4, &N1)
    }

    ; ---------------------------------------------------------------- the status bar

    ubyte[40] st_left
    ubyte[60] st_right

    sub ui_status(str s) {
        void strings.copy(s, st_left)
        vrlook.clear(WIN_L + 1, STAT_LINE + 1, STAT_SPLIT, STAT_LINE + 14)
        void vr.UseFont(vr.FONT_UI)
        void vrlook.fit(st_left, STAT_SPLIT - WIN_L - 12)
        vr.WPutString(&vrlook.sb, WIN_L + 6, STAT_LINE + 2 + vr.baselineOffset)
        vr.UseSystemFont()
    }

    sub status_modes() {
        if next_on
            void strings.copy("Play next on    ", st_right)
        else
            void strings.copy("Play next off    ", st_right)
        if repeat_on
            void strings.append(st_right, "Repeat on    ")
        else
            void strings.append(st_right, "Repeat off    ")
        if shuffle
            void strings.append(st_right, "Shuffle on")
        else
            void strings.append(st_right, "Shuffle off")
        vrlook.win_status(st_left, st_right)
    }

    ; ---------------------------------------------------------------- now playing

    const ubyte F_N = 7
    uword[F_N] @nosplit f_x = [416, 552, 416, 552, 416, 552, 416]
    uword[F_N] @nosplit f_y = [116, 116, 130, 130, 144, 144, 164]
    ubyte[F_N] f_w = [64, 64, 64, 64, 64, 64, 200]
    str L0 = "Kind"
    str L1 = "Format"
    str L2 = "Size"
    str L3 = "Rate"
    str L4 = "Track"
    str L5 = "Frames"
    str L6 = "Time"
    uword[F_N] @nosplit f_label = [&L0, &L1, &L2, &L3, &L4, &L5, &L6]
    ubyte[40] fs                    ; a field's text

    sub labels() {
        ubyte i
        for i in 0 to F_N - 1
            vr.WPutString(f_label[i], f_x[i] - 64, f_y[i])
        vr.WHorizontalLine($aa, RP_X, RP_R - 9, 101)
        ; the progress bar
        vr.ColorRect(PROG_COL, PROG_W, PROG_ROW, 1, vrlook.CHROME)
        vr.WFrameRectangle($ff, (PROG_COL as uword) * 8 - 1, (PROG_ROW as uword) * 8 - 1, ((PROG_COL + PROG_W) as uword) * 8, (PROG_ROW as uword) * 8 + 8)
        ; the lights under play, pause and stop
        for i in 1 to 3 {
            uword x = ((ICON_COL0 + 5 * i + 1) as uword) * 8
            vr.WFrameRectangle($ff, x - 1, (LED_ROW as uword) * 8 - 1, x + 16, (LED_ROW as uword) * 8 + 8)
        }
    }

    sub field(ubyte i, str s) {
        vrlook.field_text(s, f_x[i], f_y[i], f_w[i], i == 6)
    }

    sub leds(bool playing, bool paused) {
        ; the lights: play green, pause yellow, stop red
        alias c = cx16.r5L                 ; (each value passed before the next call)
        c = 0
        if playing and not paused
            c = vrlook.GREEN
        vr.ColorRect(ICON_COL0 + 6, 2, LED_ROW, 1, c)
        c = 0
        if playing and paused
            c = vrlook.YELLOW
        vr.ColorRect(ICON_COL0 + 11, 2, LED_ROW, 1, c)
        c = vrlook.RED
        if playing
            c = 0
        vr.ColorRect(ICON_COL0 + 16, 2, LED_ROW, 1, c)
    }

    sub map_colour(ubyte x, ubyte w, ubyte row, ubyte c) {
        ; the colour map written directly (while media plays: no kernel calls)
        cx16.VERA_CTRL = 0
        cx16.VERA_ADDR_L = x * 2 + 1
        cx16.VERA_ADDR_M = $AC + row
        cx16.VERA_ADDR_H = $21              ; increment 2: the attribute bytes
        repeat w
            cx16.VERA_DATA0 = c << 4
    }

    sub progress_clear() {
        vr.ColorRect(PROG_COL, PROG_W, PROG_ROW, 1, vrlook.CHROME)
    }

    sub mmss(uword s) {
        ; s as m:ss appended to fs
        void strings.append(fs, conv.str_uw(s / 60))
        void strings.append(fs, ":")
        ubyte r = lsb(s % 60)
        if r < 10
            void strings.append(fs, "0")
        void strings.append(fs, conv.str_ub(r))
    }

    sub ui_track() {
        ; the entry selected or playing: its name and what its header says
        ubyte e = playing_ent
        if e == $FF
            e = sel
        vrlook.clear(RP_X, 70, RP_R - 2, 97)
        vrlook.clear(RP_X, 242, RP_R - 2, RP_B - 2)
        ubyte i
        m_kind = K_NONE
        if e < n_ent {
            ent_get(e)
            if cur[0] == 'V' or cur[0] == 'A'
                media_info(&cur + 1)
        }
        if m_kind == K_NONE {
            vrlook.field_text("Nothing selected.", RP_X, 80, 260, true)
            for i in 0 to F_N - 1
                field(i, "")
            leds(false, false)
            return
        }
        vrlook.field_text(&cur + 1, RP_X, 80, 260, true)
        vrlook.field_text(&vr.curDirName, RP_X, 94, 260, false)
        base_of(&cur + 1, &mbase)
        mark_val = mark_get(&mbase)
        ; the fields
        if m_kind == K_VIDEO {
            if m_vtype == 3 or m_vtype == 8 or m_vtype == 23 or m_vtype == 28
                void strings.copy("Bitmap", fs)
            else
                void strings.copy("Sprite", fs)
            if m_spi
                void strings.append(fs, " HB")
            field(0, fs)
            void strings.copy(conv.str_ub(m_bpp), fs)
            void strings.append(fs, " bpp")
            field(1, fs)
            void strings.copy(conv.str_uw(m_w), fs)
            void strings.append(fs, " x ")
            void strings.append(fs, conv.str_uw(m_h))
            field(2, fs)
            void strings.copy(conv.str_ub(m_fps), fs)
            void strings.append(fs, " fps")
            field(3, fs)
            void strings.copy(conv.str_l(m_frames), fs)
            field(5, fs)
        } else {
            if m_kind == K_WAV
                field(0, "WAV")
            else
                field(0, "ZCM")
            if m_16bit
                void strings.copy("16-bit ", fs)
            else
                void strings.copy("8-bit ", fs)
            if m_stereo
                void strings.append(fs, "stereo")
            else
                void strings.append(fs, "mono")
            field(1, fs)
            void strings.copy(conv.str_l(m_bytes / 1024), fs)
            void strings.append(fs, " KB")
            field(2, fs)
            void strings.copy(conv.str_l(m_hz), fs)
            void strings.append(fs, " Hz")
            field(3, fs)
            field(5, "")
        }
        track_count(e)
        void strings.copy(conv.str_ub(track_no), fs)
        void strings.append(fs, " of ")
        void strings.append(fs, conv.str_ub(n_media))
        field(4, fs)
        fs[0] = 0
        mmss(mark_secs(mark_val))
        void strings.append(fs, "  /  ")
        mmss(m_secs)
        field(6, fs)
        ; the lower lines
        mark_line()
        if m_kind == K_VIDEO {
            if m_spi
                vrlook.field_text("High bandwidth: plays from the SD card only.", RP_X, 252, 260, false)
            else
                vrlook.field_text("Plays full screen; Veranda comes back after.", RP_X, 252, 260, false)
        } else {
            ; (the keys: the Deck's legend)
            vrlook.field_text("Plays here: the disc turns in the deck.", RP_X, 252, 260, false)
            vrlook.field_text("The buttons work while it plays.", RP_X, 268, 260, false)
        }
        leds(false, false)
    }

    sub track_count(ubyte e) {
        track_no = 0
        ubyte i
        for i in 0 to e {
            ent_get(i)
            if cur[0] == 'V' or cur[0] == 'A'
                track_no++
        }
        ent_get(e)
    }

    ; ---------------------------------------------------------------- the media's header

    sub media_info(str name) {
        ; what the file's own header says (Veranda's file calls)
        m_kind = K_NONE
        m_secs = 0
        ubyte l = strings.length(name)
        if l < 5
            return
        ubyte h = vr.FOpen(name, 'r')
        if h < 2
            return
        sys.memset(&hdr, 48, 0)
        void vr.FRead(h, &hdr, 48)
        void vr.FClose(h)
        ubyte c = name[l - 3] | $20
        if c == 's' {
            if hdr[0] != 'S' or hdr[1] != 'P' or hdr[2] != 'R' or hdr[3] != 'V'
                return
            m_kind = K_VIDEO
            m_vtype = hdr[4]
            m_bpp = hdr[5]
            m_fps = hdr[6]
            m_w = mkword(hdr[10], hdr[9])
            m_h = mkword(hdr[12], hdr[11])
            m_frames = mklong2(mkword(hdr[16], hdr[15]), mkword(hdr[14], hdr[13]))
            m_spi = m_vtype > 20
            if m_fps != 0
                m_secs = lsw(m_frames / m_fps)
        } else if c == 'w' {
            m_kind = K_WAV
            m_stereo = hdr[22] == 2
            m_16bit = hdr[34] == 16
            m_hz = mklong2(mkword(hdr[27], hdr[26]), mkword(hdr[25], hdr[24]))
            m_rate = mklong2(mkword(hdr[31], hdr[30]), mkword(hdr[29], hdr[28]))
            m_bytes = mklong2(mkword(hdr[43], hdr[42]), mkword(hdr[41], hdr[40]))
        } else if c == 'z' {
            m_kind = K_ZCM
            m_16bit = hdr[6] & $20 != 0
            m_stereo = hdr[6] & $10 != 0
            m_hz = (hdr[7] as long) * 48828 / 128
            m_rate = m_hz
            if m_stereo
                m_rate *= 2
            if m_16bit
                m_rate *= 2
            if hdr[0] == $FF and hdr[1] == $FF
                m_bytes = mklong2(mkword(hdr[5], hdr[4]), mkword(hdr[3], hdr[2]))
            else
                m_bytes = (mkword(hdr[5], hdr[4]) as long) * 256 + hdr[3]
        }
        if (m_kind == K_WAV or m_kind == K_ZCM) and m_rate != 0
            m_secs = lsw(m_bytes / m_rate)
    }

    ; ================================================================= the playlist

    sub slot(ubyte i) -> uword {
        ; maps entry i's bank (the caller puts its own back)
        cx16.ram_bank = ent_bank + (i >> 7)
        return $A000 + ((i & 127) as uword) * 64
    }

    sub ent_get(ubyte i) {
        alias b = cx16.r5L
        b = cx16.ram_bank
        sys.memcopy(slot(order[i]), &cur, 64)
        cx16.ram_bank = b
    }

    sub ent_put(ubyte kind, str name) {
        alias b = cx16.r5L
        alias p = cx16.r6
        b = cx16.ram_bank
        p = slot(n_ent)
        order[n_ent] = n_ent
        @(p) = kind
        void strings.ncopy(name, p + 1, 62)
        @(p + 63) = 0
        cx16.ram_bank = b
        n_ent++
    }

    sub lower(ubyte c) -> ubyte {
        if c >= 'A' and c <= 'Z'
            return c + 32
        return c
    }

    sub media_kind(str s) -> ubyte {
        ; 'V' an SPV, 'A' a WAV or ZCM, 0 neither
        alias l = cx16.r5L
        alias a = cx16.r5H
        alias b = cx16.r6L
        alias c = cx16.r6H
        l = strings.length(s)
        if l < 5 or s[l - 4] != '.'
            return 0
        a = lower(s[l - 3])
        b = lower(s[l - 2])
        c = lower(s[l - 1])
        if a == 's' and b == 'p' and c == 'v'
            return 'V'
        if (a == 'w' and b == 'a' and c == 'v') or (a == 'z' and b == 'c' and c == 'm')
            return 'A'
        return 0
    }

    sub at_root() -> bool {
        return vr.curDirName[1] == 0
    }

    sub list_read() {
        ; the whole listing before any file is opened (on the SD card a file
        ; opened ends a listing: Veranda V16); folders, then the media
        n_ent = 0
        n_media = 0
        if not at_root()
            ent_put('U', "..")
        ubyte pass
        for pass in 0 to 1 {
            if vr.DirOpen("*") != 0
                continue
            while vr.DirNext(&dirent) == 0 and n_ent < ENT_MAX {
                uword nm = &dirent + 3
                if @(nm) == '.' and (@(nm + 1) == 0 or (@(nm + 1) == '.' and @(nm + 2) == 0))
                    continue
                if pass == 0 and dirent[0] == 'D'
                    ent_put('D', nm)
                else if pass == 1 and dirent[0] == 'F' {
                    ubyte k = media_kind(nm)
                    if k != 0 {
                        if strings.length(nm) >= 62
                            k = 'L'
                        ent_put(k, nm)
                        n_media++
                    }
                }
            }
        }
        list_sort()
        top = 0
        sel = 0
    }

    ubyte[64] cmp_b

    sub ent_cmp(ubyte a, ubyte b) -> byte {
        ; slots a and b in order: "..", folders, media; then the name, case ignored
        alias save = cx16.r6H
        alias x = cx16.r5L
        alias y = cx16.r5H
        alias i = cx16.r6L
        save = cx16.ram_bank
        sys.memcopy(slot(a), &cur, 64)
        sys.memcopy(slot(b), &cmp_b, 64)
        cx16.ram_bank = save
        x = rank(cur[0])
        y = rank(cmp_b[0])
        if x != y {
            if x < y
                return -1
            return 1
        }
        for i in 1 to 63 {
            x = lower(cur[i])
            y = lower(cmp_b[i])
            if x != y {
                if x < y
                    return -1
                return 1
            }
            if x == 0
                break
        }
        return 0
    }

    sub rank(ubyte t) -> ubyte {
        if t == 'U'
            return 0
        if t == 'D'
            return 1
        return 2
    }

    sub list_sort() {
        alias i = cx16.r8L                 ; (not r5, r6: ent_cmp's)
        alias j = cx16.r8H
        alias t = cx16.r9L
        if n_ent < 2
            return
        for i in 1 to n_ent - 1 {
            t = order[i]
            j = i
            while j != 0 and ent_cmp(order[j - 1], t) > 0 {
                order[j] = order[j - 1]
                j--
            }
            order[j] = t
        }
    }

    ; ---------------------------------------------------------------- drawing it

    ubyte thumb_a = $FF
    ubyte thumb_n = $FF

    sub list_head() {
        vrlook.clear(LIST_X + 4, 49, LP_R - 1, 61)
        vr.currentMode = vr.SET_BOLD
        vr.WPutString("Playlist", LIST_X + 6, 59)
        vr.currentMode = 0
        void vrlook.fit(&vr.curDirName, 150)
        vr.WPutString(&vrlook.sb, LIST_X + 62, 59)
        void strings.copy(conv.str_ub(n_media), fs)
        if n_media == 1
            void strings.append(fs, " file")
        else
            void strings.append(fs, " files")
        vr.WPutString(&fs, LP_R - 8 - vrlook.strw(fs), 59)
    }

    sub list_mark(ubyte r, bool on) {
        ubyte c = 0
        if on {
            c = vrlook.hilite
            if c == 0
                c = vrlook.SELECT
        }
        vr.ColorRect(LIST_COL, SB_COL - LIST_COL, lsb(LIST_Y >> 3) + 2 * r, 2, c)
    }

    sub list_row(ubyte r) {
        ubyte e = top + r
        uword y = LIST_Y + (r as uword) * ROW_H
        vrlook.clear(LIST_X, y, LIST_XR, y + ROW_H - 1)
        list_mark(r, e == sel and e < n_ent)
        if e >= n_ent
            return
        ent_get(e)
        uword pic = &pic_note
        if cur[0] == 'U'
            pic = &pic_up
        else if cur[0] == 'D'
            pic = &pic_folder
        else if cur[0] == 'V'
            pic = &pic_film
        if e == playing_ent
            vr.WBitmapUp(&pic_playing, LIST_COL, 1, y + 4, 8)
        vr.WBitmapUp(pic, LIST_COL + 1, 1, y + 4, 8)
        vr.currentMode = 0
        if e == playing_ent
            vr.currentMode = vr.SET_BOLD
        if cur[0] == 'U'
            void vrlook.fit("..", LIST_XR - 36)
        else
            void vrlook.fit(&cur + 1, LIST_XR - 36)
        vr.WPutString(&vrlook.sb, LIST_X + 18, y + 11)
        vr.currentMode = 0
    }

    sub list_bar() {
        ubyte a = 0
        ubyte n = SB_TRACK
        if n_ent > LIST_N {
            a = lsb((top as uword) * SB_TRACK / n_ent)
            n = lsb((LIST_N as uword) * SB_TRACK / n_ent)
            if n == 0
                n = 1
            if a + n > SB_TRACK
                a = SB_TRACK - n
        }
        if a == thumb_a and n == thumb_n
            return
        vr.ColorRect(SB_COL, 1, SB_ROW0 + 1, SB_TRACK, vrlook.CHROME)
        vr.ColorRect(SB_COL, 1, SB_ROW0 + 1 + a, n, vrlook.SELECT)
        thumb_a = a
        thumb_n = n
    }

    sub list_draw() {
        ubyte r
        for r in 0 to LIST_N - 1
            list_row(r)
        list_bar()
    }

    sub panel() {
        vrlook.clear(LIST_X, LIST_Y, LP_R - 1, LP_B - 1)
        vr.WVerticalLine($ff, (SB_COL as uword) * 8 - 1, LP_T + 17, LP_B)
        vr.WBitmapUp(&pic_arrow_up, SB_COL, 1, (SB_ROW0 as uword) * 8, 8)
        vr.WBitmapUp(&pic_arrow_down, SB_COL, 1, (SB_ROWN as uword) * 8, 8)
        thumb_a = $FF
        thumb_n = $FF
        list_head()
        list_draw()
    }

    sub row_of(ubyte e) {
        if e != $FF and e >= top and e < top + LIST_N
            list_row(e - top)
    }

    sub scroll_to(word t) {
        alias most = cx16.r5s
        most = 0
        if n_ent > LIST_N
            most = (n_ent - LIST_N) as word
        if t > most
            t = most
        if t < 0
            t = 0
        if lsb(t) == top
            return
        top = lsb(t)
        list_draw()
    }

    sub select_entry(word e) {
        if n_ent == 0
            return
        if e < 0
            e = 0
        if e >= (n_ent as word)
            e = (n_ent - 1) as word
        alias old = cx16.r5L
        alias t = cx16.r5H
        old = sel
        t = top
        sel = lsb(e)
        if sel < top
            top = sel
        else if sel >= top + LIST_N
            top = sel - LIST_N + 1
        if top != t
            list_draw()
        else {
            if old >= top and old < top + LIST_N
                list_mark(old - top, false)
            list_mark(sel - top, true)
        }
        if playing_ent == $FF
            ui_track()
    }

    ; ---------------------------------------------------------------- folders

    sub enter(str name) {
        ubyte l
        if name[0] == '.' and name[1] == '.' {
            if at_root() or vr.ChDir("..") != 0
                return
            l = strings.length(&vr.curDirName)
            while l > 1 {
                l--
                if vr.curDirName[l] == '/'
                    break
            }
            if l == 0
                l = 1
            vr.curDirName[l] = 0
        } else {
            l = strings.length(&vr.curDirName)
            if l + strings.length(name) + 2 > 61 or vr.ChDir(name) != 0 {
                ui_status("Cannot open the folder")
                vr.Beep()
                return
            }
            if l > 1 {
                vr.curDirName[l] = '/'
                l++
            }
            void strings.copy(name, &vr.curDirName + l)
        }
        ui_list()
    }

    sub ui_list() {
        void vr.SetPointer(vr.PTR_BUSY)
        list_read()
        void vr.SetPointer(vr.PTR_ARROW)
        playing_ent = $FF
        panel()
        ui_track()
    }

    sub open_entry(ubyte e) {
        ent_get(e)
        if cur[0] == 'D' or cur[0] == 'U' {
            void strings.copy(&cur + 1, tmpname)
            enter(tmpname)
        } else
            ask_play(e)
    }

    ; ================================================================= bookmarks
    ; NAME.MARK beside the media (NAME its name less the extension), one 5-byte
    ; CBM float - the standalone VIDKIT players' own bookmarks (PLAYMOVIES and
    ; the rest), so either resumes the other's: a video's frame, or audio's
    ; position in the file in bytes. Written when a file is stopped part way,
    ; deleted when it plays to its end or is restarted.

    ubyte[72] mark_name
    ubyte[5]  mflpt
    ubyte[64] mbase
    long  mark_val                      ; the selected file's bookmark (ui_track): 0 none
    bool  quiet_once                    ; the next play is part of a run (Play all): no question
    ubyte[26] mark_text

    sub mark_file(uword basename) {
        void strings.copy(basename, &mark_name)
        void strings.append(&mark_name, ".MARK")
    }

    sub mark_get(uword basename) -> long {
        ; the bookmark of basename (m_kind, m_frames, m_bytes the file's: media_info); 0 none
        mark_file(basename)
        ubyte h = vr.FOpen(&mark_name, 'r')
        if h < 2
            return 0
        sys.memset(&mflpt, 5, 0)
        uword got = vr.FRead(h, &mflpt, 5)
        void vr.FClose(h)
        if got != 5
            return 0
        long v = mflpt_get()
        if m_kind == K_VIDEO {
            if v <= 5 or v >= m_frames - 10      ; (as PLAYMOVIES: near either end, none)
                return 0
        } else if v <= 0 or v >= m_bytes
            return 0
        return v
    }

    sub mark_line() {
        ; the Now playing panel's last line: the bookmark, if any
        vrlook.clear(RP_X, 292, RP_R - 2, RP_B - 2)
        if mark_val > 0 {
            void strings.copy("Bookmarked at ", fs)
            mmss(mark_secs(mark_val))
            void strings.append(fs, ": it can resume there.")
            vrlook.field_text(fs, RP_X, 300, 260, false)
        }
    }

    sub mark_put(uword basename, long v) {
        mark_file(basename)
        mflpt_set(v)
        ubyte h = vr.FOpen(&mark_name, 'w')
        if h < 2
            return
        void vr.FWrite(h, &mflpt, 5)
        void vr.FClose(h)
    }

    sub mark_del(uword basename) {
        mark_file(basename)
        void vr.FDelete(&mark_name)
    }

    sub mflpt_set(long n) {
        ; n (0 or more) as a CBM 5-byte float: exponent 128 + bits, then the
        ; mantissa from its top bit, whose place holds the sign (0: positive)
        sys.memset(&mflpt, 5, 0)
        if n <= 0
            return
        alias k = cx16.r5L
        alias i = cx16.r5H
        alias t = cx16.r8r9sl
        k = 0
        t = n
        while t != 0 {
            t >>= 1
            k++
        }
        mflpt[0] = 128 + k
        for i in 0 to k - 1 {
            if ((n >> (k - 1 - i)) & 1) != 0
                mflpt[1 + i / 8] |= $80 >> (i & 7)
        }
        mflpt[1] &= $7F
    }

    sub mflpt_get() -> long {
        ; the CBM 5-byte float in mflpt as a whole number (a fraction dropped; < 0: 0)
        if mflpt[0] <= 128 or (mflpt[1] & $80) != 0
            return 0
        alias k = cx16.r5L
        alias i = cx16.r5H
        alias b = cx16.r6L
        alias v = cx16.r8r9sl
        k = mflpt[0] - 128
        if k > 31
            return $7FFFFFFF
        v = 0
        for i in 0 to k - 1 {
            b = mflpt[1 + i / 8]
            if i < 8
                b |= $80
            v <<= 1
            if (b & ($80 >> (i & 7))) != 0
                v++
        }
        return v
    }

    sub pos_to_jiffies(long pos) -> long {
        ; audio: a byte position to a time (m_rate the file's bytes a second)
        if m_rate == 0
            return 0
        alias secs = cx16.r8r9sl
        alias rem = cx16.r6r7sl
        secs = pos / m_rate
        rem = pos - secs * m_rate
        return secs * 60 + (rem * 60 + m_rate / 2) / m_rate
    }

    sub jiffies_to_pos(long j) -> long {
        ; audio: a time to a byte position, up to a whole sample (as PLAYMOVIES)
        alias secs = cx16.r8r9sl
        alias rem = cx16.r6r7sl
        alias pos = cx16.r10r11sl
        alias blk = cx16.r5L
        secs = j / 60
        rem = j - secs * 60
        pos = secs * m_rate + rem * m_rate / 60
        blk = 1
        if m_16bit
            blk *= 2
        if m_stereo
            blk *= 2
        while (lsb(pos) & (blk - 1)) != 0
            pos++
        return pos
    }

    sub mark_secs(long v) -> uword {
        ; a bookmark as seconds into the file
        if m_kind == K_VIDEO {
            if m_fps == 0
                return 0
            return lsw(v / m_fps)
        }
        if m_rate == 0
            return 0
        return lsw(v / m_rate)
    }

    ubyte[] box_resume = [vr.DEF_DB_POS | 1,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_1_Y, 0, 0,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_2_Y, 0, 0,
        vr.DBTXTSTR, vr.TXT_LN_X, vr.TXT_LN_4_Y, 0, 0,
        vr.YES, vr.DBI_X_0, vr.DBI_Y_2,
        vr.NO, vr.DBI_X_1, vr.DBI_Y_2,
        vr.CANCEL, vr.DBI_X_2, vr.DBI_Y_2,
        0]
    str R1 = "Resume where it stopped?"
    str R3 = "Yes resume, No restart"

    sub ask_resume() -> ubyte {
        ; Resume (YES), Restart (NO) or CANCEL
        pokew(&box_resume + 4, &R1)
        void strings.copy("(the bookmark: ", &mark_text)
        fs[0] = 0
        mmss(mark_secs(mark_val))
        void strings.append(&mark_text, fs)
        void strings.append(&mark_text, ")")
        pokew(&box_resume + 9, &mark_text)
        pokew(&box_resume + 14, &R3)
        ubyte ans = vr.DoDlgBox(&box_resume)
        void take_wheel()
        return ans
    }

    ; ================================================================= playing

    sub ask_play(ubyte e) {
        pending = P_PLAY
        pending_ent = e
    }

    sub ask_step(byte d) {
        pending = P_STEP
        pending_dir = d
    }

    sub play_selected() {
        if n_ent != 0 and sel < n_ent {
            ent_get(sel)
            if cur[0] == 'V' or cur[0] == 'A' {
                ask_play(sel)
                return
            }
        }
        ask_step(1)
    }

    ubyte[64] base

    ubyte[vkx.CHAIN_MAX] chain_ent      ; the run of videos handed to vkx: their entries
    uword chain_names                   ; their names, CHAIN_NAME bytes each (a slab)
    const ubyte CHAIN_NAME = 32         ; (a longer name ends the run: Play next goes on from the window)

    sub base_of(uword name, uword dst) {
        ; the name without its extension (VIDKIT finds .SPV, .WAV, .ZCM itself)
        void strings.ncopy(name, dst, 63)
        ubyte l = strings.length(dst)
        if l > 4 and @(dst + l - 4) == '.'
            @(dst + l - 4) = 0
    }

    sub build_chain(ubyte e) {
        ; a video with Repeat on: the same again in the same excursion; with
        ; Play next (or Shuffle) on: the videos that would follow it (up to an
        ; audio file, CHAIN_MAX of them) - played one after another, no window
        ; between. Shuffle alone goes on to the next only when Tab skips
        vkx.chain_len = 0
        vkx.chain_repeat = repeat_on
        vkx.chain_auto = next_on
        if repeat_on or not (next_on or shuffle)
            return
        if chain_names == 0
            chain_names = memory("chain_names", vkx.CHAIN_MAX * CHAIN_NAME, 0)
        ubyte k
        ubyte from = e
        for k in 0 to vkx.CHAIN_MAX - 1 {
            ubyte nx = pick(from, 1, e)
            if nx == $FF
                break
            ent_get(nx)
            if cur[0] != 'V' or strings.length(&cur + 1) >= CHAIN_NAME     ; (base_of copies the whole name first)
                break
            chain_ent[k] = nx
            uword p = chain_names + (k as uword) * CHAIN_NAME
            base_of(&cur + 1, p)
            vkx.chain[k] = p
            media_info(&cur + 1)            ; (its frames: mark_get checks the bookmark)
            vkx.chain_start[k] = mark_get(p)
            vkx.chain_len++
            from = nx
        }
        ent_get(e)
        media_info(&cur + 1)                ; (the first one's again)
    }

    sub play_entry(ubyte e) {
        ; plays entry e now, and what follows it (repeat, the next one)
        ent_get(e)
        if cur[0] == 'L' {
            ui_status("The name is too long to play")
            vr.Beep()
            return
        }
        if cur[0] != 'V' and cur[0] != 'A'
            return
        ubyte was = playing_ent
        playing_ent = e
        row_of(was)
        select_entry(e)
        row_of(e)
        ui_track()                          ; (media_info: m_kind ...)
        base_of(&cur + 1, &base)
        ; a bookmark: asked (a file chosen to play), or used (a run: Play next,
        ; Repeat, Play all); Restart deletes it
        long start = mark_val
        if start > 0 {
            ubyte ans = vr.YES
            if not (next_on or repeat_on or quiet_once)
                ans = ask_resume()
            if ans == vr.CANCEL {
                quiet_once = false
                playing_ent = $FF
                row_of(e)
                ui_status("Ready")
                return
            }
            if ans == vr.NO {
                mark_del(&base)
                start = 0
                mark_val = 0
                fs[0] = 0
                mmss(0)
                void strings.append(fs, "  /  ")
                mmss(m_secs)
                field(6, fs)
                mark_line()
            }
        }
        quiet_once = false
        step_after = 0
        last_buttons = 0
        leds_paused = false
        progress_clear()
        vkx.chain_len = 0
        vkx.chain_repeat = false
        ; Tab skips to the next file in a list (Play next or Shuffle on): VIDKIT's
        ; KEY_EXTRA; playing a single file it is no key at all
        vkx.skip_key = 0
        if next_on or shuffle
            vkx.skip_key = 9
        if m_kind == K_VIDEO {
            build_chain(e)
            vkx.start_frame = start
            ui_status("Playing (full screen)")
        } else {
            if start > 0
                vkx.start_jiffies = pos_to_jiffies(start)
            vktape.reset()
            leds(true, false)
            ui_status("Playing")
        }
        void vr.SetPointer(vr.PTR_ARROW)
        blank_hold()                        ; (until the run ends: update)
        if AUTOTEST and vr.blankDelay != 0
            test_blank_bad = true
        ubyte r = vkx.play(base)
        vktape.disc_restore()               ; (audio: palette entries 32-47 as they were)
        void take_wheel()                   ; (turns made while it played don't scroll)
        ; back: the window is Veranda's again. After a run of videos: the last
        ; one played is the one shown (shuffle: the ones before it remembered)
        if vkx.chain_played != 0 {
            ubyte k
            for k in 0 to vkx.chain_played - 1 {
                if shuffle
                    hist_push(playing_ent)
                playing_ent = chain_ent[k]
            }
            row_of(e)
            e = playing_ent
            select_entry(e)
            row_of(e)
            ui_track()
        }
        marks_after(r)
        if AUTOTEST and test_tab != 0 {
            test_tab_after(r, e)
            return
        }
        if AUTOTEST {
            if m_kind == K_VIDEO
                test_log("VP VIDEO ", r)
            else
                test_log("VP AUDIO ", r)
            if vkx.chain_played != 0
                test_log("VP CHAINED ", vkx.chain_played)
            long at = vkx.played_jiffies     ; (audio: jiffies into the file; video: its frame)
            if m_kind == K_VIDEO
                at = vkx.end_frame
            test_logl("VP AT ", at)
            test_plays++
            if test_plays == 3 {
                ; a stop part way: 8BG.WAV again, stopped by play_control after 2 s
                vkx.limit_jiffies = 0
                test_plays = 4
                ask_play(0)
                return
            }
            if test_plays > 5 {
                ; the stop with F5 on played the file again: the F5-then-Esc bug
                test_check("VP STOP AFTER F5", false)
                test_end()
                step_after = 0
                ui_status("Test done")
                playing_ent = $FF
                row_of(e)
                return
            }
            if test_plays == 5 {
                base_of("8BG.WAV", &mbase)
                test_logl("VP MARKFILE ", mark_get(&mbase))
                test_wait = 1               ; (update: a second later, nothing may be playing)
            }
        }
        leds(false, false)
        if r == vkx.NOT_FOUND {
            ui_status("VIDKIT cannot play it")
            vr.Beep()
        } else if r == vkx.NEEDS_SD {
            ui_status("High bandwidth video: SD card only")
            vr.Beep()
        } else if r == vkx.BAD_ROM {
            ui_status("VIDKIT needs ROM R48 or later")
            vr.Beep()
        } else {
            ; the time it played, in the Time field
            fs[0] = 0
            if m_kind == K_VIDEO {
                if m_fps != 0
                    mmss(lsw(vkx.end_frame / m_fps))
            } else
                mmss(lsw(vkx.played_jiffies / 60))
            void strings.append(fs, "  /  ")
            mmss(m_secs)
            field(6, fs)
            if step_after != 0 {
                ask_step(step_after)
            } else if r == vkx.SKIPPED {
                ; Tab: on to the next file (a video run went on by itself while
                ; there were videos; this is the end of it, or audio)
                ask_step(1)
                ui_status("Skipped")
            } else if r == vkx.FINISHED {
                ; repeat (or VIDKIT's F5 loop): the same again; "Play next" on: the
                ; next one; else it stops here. (A stop - Esc, Stop - ends it here,
                ; F5 or not: vkx.loop_requested is only set for a play that finished)
                if repeat_on or vkx.loop_requested
                    ask_play(e)
                else if next_on
                    ask_step(1)
                ui_status("Finished")
            } else
                ui_status("Stopped")
        }
        playing_ent = $FF
        row_of(e)
    }

    sub marks_after(ubyte r) {
        ; the bookmarks after a play: a file stopped part way gets one (where it
        ; stopped), files played to the end lose theirs. (A run of videos: the
        ; first and all but the last of the chain ended; m_* are the last one's)
        if r == vkx.SKIPPED
            r = vkx.FINISHED                ; (a skipped file: done with, as one played to its end)
        if r != vkx.FINISHED and r != vkx.STOPPED
            return
        if vkx.chain_played != 0 {
            mark_del(&base)
            ubyte k
            for k in 0 to vkx.chain_played - 1 {
                if k != vkx.chain_played - 1
                    mark_del(chain_names + (k as uword) * CHAIN_NAME)
            }
            void strings.copy(chain_names + ((vkx.chain_played - 1) as uword) * CHAIN_NAME, &base)
        }
        if r == vkx.FINISHED and not vkx.loop_requested {
            mark_del(&base)
            mark_val = 0
            mark_line()
            return
        }
        if r != vkx.STOPPED
            return
        long v
        if m_kind == K_VIDEO
            v = vkx.end_frame
        else
            v = jiffies_to_pos(vkx.played_jiffies)
        mark_val = 0
        if m_kind == K_VIDEO {
            if v > 5 and v < m_frames - 10
                mark_val = v
        } else if v > 0 and v < m_bytes
            mark_val = v
        if mark_val > 0
            mark_put(&base, mark_val)
        else
            mark_del(&base)
        mark_line()
    }

    sub hist_push(ubyte e) {
        if n_hist == 16 {
            sys.memcopy(&hist + 1, &hist, 15)
            n_hist--
        }
        hist[n_hist] = e
        n_hist++
    }

    sub pick(ubyte from, byte d, ubyte avoid) -> ubyte {
        ; the file after (d 1) or before (d -1) entry `from`, wrapping at the ends;
        ; shuffle and forward: a random one (not `from` or `avoid`); $FF: none
        ubyte e
        if n_media == 0
            return $FF
        if shuffle and d > 0 and n_media > 1 {
            ubyte k
            for k in 1 to 200 {
                vr.GetRandom()
                e = lsb(vr.random % n_ent)
                ent_get(e)
                if (cur[0] == 'V' or cur[0] == 'A') and e != from and (e != avoid or n_media < 3)
                    return e
            }
        }
        e = from
        ubyte n
        for n in 1 to n_ent {
            if d > 0 {
                e++
                if e >= n_ent
                    e = 0
            } else {
                if e == 0
                    e = n_ent - 1
                else
                    e--
            }
            ent_get(e)
            if cur[0] == 'V' or cur[0] == 'A'
                return e
        }
        return $FF
    }

    sub step_track(byte d) {
        ; the next or previous file (shuffle: a random one, back through the
        ; ones played), wrapping at the ends of the list
        if shuffle and d < 0 and n_hist != 0 {
            n_hist--
            ask_play(hist[n_hist])
            return
        }
        ubyte e = pick(sel, d, sel)
        if e == $FF
            return
        if shuffle and d > 0
            hist_push(sel)
        ask_play(e)
    }

    ; ---------------------------------------------------------------- while media plays

    sub play_control() {
        ; vkx's control routine, every frame while media plays (Veranda parked:
        ; no kernel calls): the mouse, the transport buttons, the pause light
        if AUTOTEST and test_plays == 4 {
            ; the stop part way, with VIDKIT's loop (F5) on a second before it
            if vkx.elapsed_jiffies() > 60
                vkx.VK_LOOP_FLAG = 1
            if vkx.elapsed_jiffies() > 120
                vkx.stop_request = true
        }
        if AUTOTEST and test_tab != 0 {
            ; the Tab tests: Tab at the 30th call (VIDKIT's key controller reads
            ; it this frame; not in the third play), a stop at the test_tab_at'th
            test_ctl++
            if test_ctl == 30 and test_tab != 3 {
                %asm {{
                    lda  #9
                    jsr  $fec3              ; kbdbuf_put: Tab
                }}
            }
            if test_ctl == test_tab_at
                vkx.stop_request = true
        }
        vkx.mouse_poll()
        if m_kind == K_VIDEO
            return
        alias down = cx16.r5L               ; (VIDKIT's r0-r15 are kept around this call: vkx.user_call)
        alias col = cx16.r5H
        alias x = cx16.r6
        alias y = cx16.r8
        alias p = cx16.r9bL
        down = vkx.mouse_buttons & 1
        if down != 0 and last_buttons == 0 {
            x = vkx.mouse_x
            y = vkx.mouse_y
            if y >= ICON_Y and y < ICON_Y + 24 {
                col = lsb(x >> 3)
                if col >= ICON_COL0 and col < ICON_COL0 + 4 {
                    step_after = -1
                    vkx.stop_request = true
                } else if col >= ICON_COL0 + 5 and col < ICON_COL0 + 9 {
                    vkx.pause_request = false
                } else if col >= ICON_COL0 + 10 and col < ICON_COL0 + 14 {
                    vkx.pause_request = not vkx.pause_request
                } else if col >= ICON_COL0 + 15 and col < ICON_COL0 + 19 {
                    vkx.stop_request = true
                } else if col >= ICON_COL0 + 20 and col < ICON_COL0 + 24 {
                    step_after = 1
                    vkx.stop_request = true
                }
            }
        }
        last_buttons = down
        p = vkx.pause_request or vkx.paused
        if p != leds_paused {
            leds_paused = p
            if p {
                map_colour(ICON_COL0 + 6, 2, LED_ROW, 0)
                map_colour(ICON_COL0 + 11, 2, LED_ROW, vrlook.YELLOW)
            } else {
                map_colour(ICON_COL0 + 6, 2, LED_ROW, vrlook.GREEN)
                map_colour(ICON_COL0 + 11, 2, LED_ROW, 0)
            }
        }
    }

    ; ================================================================= the buttons, the pointer, the keys

    sub icons_on() {
        ; the transport buttons: GEOS icons (DoIcons), flashed when clicked
        icons[0] = 5
        icons[1] = 0
        icons[2] = 0
        icons[3] = 0
        icon(0, &pic_prev, ICON_COL0, &i_prev)
        icon(1, &pic_play, ICON_COL0 + 5, &i_play)
        icon(2, &pic_pause, ICON_COL0 + 10, &i_pause)
        icon(3, &pic_stop, ICON_COL0 + 15, &i_stop)
        icon(4, &pic_next, ICON_COL0 + 20, &i_next)
        vr.iconSelFlg = vr.ST_FLASH
        vr.DoIcons(&icons)
    }

    sub icon(ubyte i, uword pic, ubyte x, uword routine) {
        uword p = &icons + 4 + (i as uword) * 8
        pokew(p, pic)
        @(p + 2) = x
        @(p + 3) = ICON_Y
        @(p + 4) = 4
        @(p + 5) = 24
        pokew(p + 6, routine)
    }

    sub i_prev() { ask_step(-1) }
    sub i_play() { play_selected() }
    sub i_pause() { }                       ; (only while media plays: play_control)
    sub i_stop() { }
    sub i_next() { ask_step(1) }

    sub pressed() {
        if vr.mouseData & $80 != 0
            return                          ; a release
        uword x
        uword y
        do {
            x = vr.mouseXPos
            y = vr.mouseYPosW
        } until x == vr.mouseXPos and y == vr.mouseYPosW
        if y < LIST_Y and vrlook.win_hit(x, y) == vrlook.VW_XCLOSE {
            quit()
        }
        if y < LIST_Y or y >= LIST_Y + (LIST_N as uword) * ROW_H
            return
        if x >= (SB_COL as uword) * 8 and x < (SB_COL as uword) * 8 + 8 {
            ubyte r = lsb(y >> 3)
            if r == SB_ROW0
                scroll_to((top as word) - 1)
            else if r == SB_ROWN
                scroll_to((top as word) + 1)
            else if r < SB_ROW0 + 1 + thumb_a
                scroll_to((top as word) - (LIST_N - 1))
            else if r >= SB_ROW0 + 1 + thumb_a + thumb_n
                scroll_to((top as word) + (LIST_N - 1))
            return
        }
        if x < LIST_X or x > LIST_XR
            return
        ubyte e = top + lsb((y - LIST_Y) / ROW_H)
        if e >= n_ent
            return
        if e == sel and vr.dblClickCount != 0 {
            vr.dblClickCount = 0
            open_entry(e)
            return
        }
        select_entry(e)
        vr.dblClickCount = vr.CLICK_COUNT
    }

    sub key() {
        alias k = cx16.r5L
        k = vr.keyData
        if vr.menuNumber != 0
            return
        when k {
            ' ' -> play_selected()
            vr.KEY_RIGHT -> ask_step(1)
            vr.KEY_UP -> select_entry((sel as word) - 1)
            vr.KEY_DOWN -> select_entry((sel as word) + 1)
            vr.KEY_PGUP -> select_entry((sel as word) - (LIST_N - 1))
            vr.KEY_PGDN -> select_entry((sel as word) + (LIST_N - 1))
            vr.KEY_HOME -> select_entry(0)
            vr.KEY_END -> select_entry(255)
            vr.CR -> {
                if n_ent != 0
                    open_entry(sel)
            }
            vr.KEY_LEFT -> {
                if vr.keyDataMods & vr.KEYM_ARROW != 0
                    ask_step(-1)
                else
                    enter("..")
            }
            vr.SHORTCUT | 'q' -> quit()
        }
    }

    ; ---------------------------------------------------------------- the main loop

    ; the test build (make test sets it): plays the folder from its first file
    ; with "Play next" on, each file for four seconds, logging what each play
    ; gave (two videos in a row: one excursion, "VP CHAINED 1")
    const bool AUTOTEST = false
    uword test_passes
    ubyte test_plays
    ubyte test_wait
    bool  test_blank_bad
    ubyte test_tab                      ; the Tab tests' step (1 single file, 2 a list, 3 the next, 4 videos)
    ubyte test_tab_at                   ; play_control: a stop at this call
    ubyte test_ctl                      ; play_control's calls in this play
    bool  test_wheel
    ubyte test_fin                      ; update: test_end a few passes after the last play (the blanking put back)

    sub test_check(str what, bool ok) {
        ; "VP <what> OK" or "VP <what> BAD" (make test fails on a BAD)
        void strings.copy(what, fs)
        if ok
            void strings.append(fs, " OK")
        else
            void strings.append(fs, " BAD")
        vr.LogText(fs)
    }

    sub test_end() {
        ; the checks after the plays, then the line make test waits for:
        ; the blanking held off for the run (0 at each play), then put back
        test_check("VP BLANK HELD", not test_blank_bad)
        test_check("VP BLANK BACK", vr.blankDelay == 600)
        vr.LogText("VIDPLAYER TEST DONE")
        test_wait = 0
    }

    sub test_tab_after(ubyte r, ubyte e) {
        ; after each play of the Tab tests (play_entry returns straight after).
        ; The card: 8BG.WAV 0, BEEP.WAV 1, CHIME.WAV 2, then (MEDIA) DOG1.SPV 3, DOG2.SPV 4
        playing_ent = $FF
        row_of(e)
        test_ctl = 0
        when test_tab {
            1 -> {
                ; a single file: Tab is no key, it played on until stopped
                test_check("VP TAB SINGLE", r == vkx.STOPPED)
                next_on = true
                ask_play(0)
            }
            2 -> {
                ; a list: Tab skipped, the bookmark went; on to the next
                test_check("VP TAB SKIP", r == vkx.SKIPPED and mark_val == 0)
                test_tab_at = 30
                ask_step(1)
            }
            3 -> {
                ; the next one played (stopped by play_control); then videos, if
                ; the card has them: Tab in DOG1 goes straight on to DOG2
                test_check("VP TAB NEXT", e == 1)
                ent_get(3)
                if cur[0] != 'V'
                    test_tab = 4
                else {
                    test_tab_at = 120
                    ask_play(3)
                }
            }
            4 -> test_check("VP TAB VIDEOS", r == vkx.STOPPED and vkx.chain_played == 1)
        }
        test_tab++
        if test_tab == 5
            test_fin = 1
    }

    sub test_logl(str what, long v) {
        void strings.copy(what, fs)
        void strings.append(fs, conv.str_l(v))
        vr.LogText(fs)
    }

    sub test_log(str what, ubyte r) {
        void strings.copy(what, fs)
        void strings.append(fs, conv.str_ub(r))
        vr.LogText(fs)
    }

    asmsub take_wheel() -> ubyte @A {
        ; Veranda's mouseWheel ($0571, API 5): the turns since the last read, taken
        ; and cleared with interrupts off (as Veranda's own programs do)
        %asm {{
            php
            sei
            lda  $0571
            stz  $0571
            plp
            rts
        }}
    }

    sub update() {
        if AUTOTEST and test_fin != 0 {
            test_fin++
            if test_fin == 10
                test_end()
        }
        ; the wheel scrolls the playlist, 3 rows a notch (no menu open)
        alias w = cx16.r5sL
        w = take_wheel() as byte
        if w != 0 and vr.menuNumber == 0 {
            ; (in two steps: Prog8 12.3.5 kept top in a scratch register that
            ; its multiply by 3 overwrites, in the one expression)
            alias d = cx16.r6s
            d = (w as word) * 3
            scroll_to(d + (top as word))
        }
        if AUTOTEST and test_wait != 0 {
            test_wait++
            if test_wait == 60 {
                ; a second after the stop with F5 on: nothing plays again
                test_check("VP STOP AFTER F5", pending == P_NONE)
                test_wait = 0
                ; the Tab tests: a single file (Tab does nothing), then a list
                next_on = false
                vkx.limit_jiffies = 0           ; (stopped by play_control: no PLAY_TO_TIMER)
                test_tab = 1
                test_tab_at = 90
                ask_play(1)                     ; (BEEP.WAV)
            }
        }
        if AUTOTEST and test_plays == 0 {
            test_passes++
            ; the wheel (mkwav.py's W00-W19.WAV make the list longer than the
            ; panel): 2 notches down, then far up, then far down
            when test_passes {
                10 -> vr.mouseWheel = 2
                11 -> {
                    test_wheel = top == 6
                    vr.mouseWheel = 100
                }
                12 -> {
                    if top != n_ent - LIST_N
                        test_wheel = false
                    vr.mouseWheel = 156         ; (-100)
                }
                13 -> test_check("VP WHEEL", test_wheel and top == 0)
            }
            if test_passes == 30 {
                ; Play all in an empty folder: nothing to play (the entries'
                ; banks still hold this folder's: the old loop found them)
                ubyte keep = n_ent
                n_ent = 0
                m_playall()
                n_ent = keep
                test_check("VP PLAYALL EMPTY", pending == P_NONE)
                pending = P_NONE
                vr.blankDelay = 600             ; (test_end: put back after the run)
            }
            if test_passes == 60 {
                ; bookmarks: the float, then marks for the three files (a run: used, not asked)
                mflpt_set(1234)                         ; 1234 = $8B $1A $40 $00 $00
                if mflpt[0] == $8B and mflpt[1] == $1A and mflpt[2] == $40 and mflpt[3] == 0 and mflpt_get() == 1234
                    vr.LogText("VP MFLPT OK")
                else
                    vr.LogText("VP MFLPT BAD")
                mark_put("8BG", 441000)                 ; 5 s into 8BG.WAV (88200 bytes a second)
                mark_put("BAB2", 30)
                mark_put("BAB256", 40)
                next_on = true              ; (the test goes on to the next file)
                vkx.limit_jiffies = 240     ; each file 4 s, then "finished" (VIDKIT's PLAY_TO_TIMER)
                test_plays = 1
                ask_play(0)
            }
        }
        ubyte p = pending
        if p == P_NONE
            return
        pending = P_NONE
        if vr.menuNumber != 0
            vr.RecoverAllMenus()
        if p == P_PLAY
            play_entry(pending_ent)
        else if p == P_STEP
            step_track(pending_dir)
        if pending == P_NONE
            blank_release()                 ; (the run is over: nothing more to play)
    }

    ; ---------------------------------------------------------------- blanking
    ; Veranda blanks the screen after vr.blankDelay seconds without input
    ; (V184: VERA's output off). A run of plays (Play next, Repeat, Play all)
    ; has no input for as long as it lasts: the blanking is held off from
    ; the first play to the end of the run, and the delay put back then.
    bool  blank_held
    uword blank_saved

    sub blank_hold() {
        if blank_held
            return
        blank_saved = vr.blankDelay
        vr.blankDelay = 0                   ; (0: never)
        blank_held = true
    }

    sub blank_release() {
        if not blank_held
            return
        vr.blankDelay = blank_saved
        blank_held = false
    }

    ; ================================================================= pictures
    ; the MOD Player's (examples/veranda/vmp_pics.c, MIT licence): GEOS
    ; compacted bitmaps for BitmapUp; pic_film is this player's own

    ubyte[] pic_prev = [
        $DB, $3F, $FF, $FF, $FC, $40, $00, $00, $02, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $C0, $41, $01, $80, $C0, $C3,
        $01, $80, $C1, $C7, $01, $80, $C3, $CF, $01, $80, $C7, $DF, $01, $80, $CF, $FF,
        $01, $80, $C7, $DF, $01, $80, $C3, $CF, $01, $80, $C1, $C7, $01, $80, $C0, $C3,
        $01, $80, $C0, $41, $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $5F, $FF, $FF, $85, $FA, $3F, $FF,
        $FF, $FC]
    ubyte[] pic_play = [
        $DB, $3F, $FF, $FF, $FC, $40, $00, $00, $02, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $08, $00, $01, $80, $0C, $00,
        $01, $80, $0E, $00, $01, $80, $0F, $00, $01, $80, $0F, $80, $01, $80, $0F, $C0,
        $01, $80, $0F, $80, $01, $80, $0F, $00, $01, $80, $0E, $00, $01, $80, $0C, $00,
        $01, $80, $08, $00, $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $5F, $FF, $FF, $85, $FA, $3F, $FF,
        $FF, $FC]
    ubyte[] pic_pause = [
        $DB, $3F, $FF, $FF, $FC, $40, $00, $00, $02, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $1C, $70, $01, $80, $1C, $70,
        $01, $80, $1C, $70, $01, $80, $1C, $70, $01, $80, $1C, $70, $01, $80, $1C, $70,
        $01, $80, $1C, $70, $01, $80, $1C, $70, $01, $80, $1C, $70, $01, $80, $1C, $70,
        $01, $80, $1C, $70, $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $5F, $FF, $FF, $85, $FA, $3F, $FF,
        $FF, $FC]
    ubyte[] pic_stop = [
        $DB, $3F, $FF, $FF, $FC, $40, $00, $00, $02, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $1F, $F0,
        $01, $80, $1F, $F0, $01, $80, $1F, $F0, $01, $80, $1F, $F0, $01, $80, $1F, $F0,
        $01, $80, $1F, $F0, $01, $80, $1F, $F0, $01, $80, $1F, $F0, $01, $80, $1F, $F0,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $5F, $FF, $FF, $85, $FA, $3F, $FF,
        $FF, $FC]
    ubyte[] pic_next = [
        $DB, $3F, $FF, $FF, $FC, $40, $00, $00, $02, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $82, $06, $01, $80, $C3, $06,
        $01, $80, $E3, $86, $01, $80, $F3, $C6, $01, $80, $FB, $E6, $01, $80, $FF, $F6,
        $01, $80, $FB, $E6, $01, $80, $F3, $C6, $01, $80, $E3, $86, $01, $80, $C3, $06,
        $01, $80, $82, $06, $01, $80, $00, $00, $01, $80, $00, $00, $01, $80, $00, $00,
        $01, $80, $00, $00, $01, $80, $00, $00, $01, $5F, $FF, $FF, $85, $FA, $3F, $FF,
        $FF, $FC]
    ubyte[] pic_folder = [$83, $00, $70, $8F, $03, $81, $82, $FF, $00]
    ubyte[] pic_note = [$88, $0C, $0A, $09, $08, $38, $78, $30, $00]
    ubyte[] pic_up = [$88, $10, $38, $54, $10, $10, $1E, $00, $00]
    ubyte[] pic_playing = [$88, $40, $60, $70, $78, $70, $60, $40, $00]
    ubyte[] pic_arrow_up = [$84, $FF, $81, $99, $BD, $03, $81, $81, $FF]
    ubyte[] pic_arrow_down = [$81, $FF, $03, $81, $84, $BD, $99, $81, $FF]
    ; a strip of film: sprocket holes either side of a frame
    ubyte[] pic_film = [$88, $FF, $A5, $81, $BD, $BD, $81, $A5, $FF]
}
