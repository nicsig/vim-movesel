vim9script

# FIXME:
# We've modified how to reselect a block when moving one to the left/right.
# It doesn't work as expected when alternating between the 2 motions.
#
# Make some tests with bulleted lists whose 1st line is prefixed by `-`.
#
# Also, try to move this diagram (left, right):
#
#                            ← bottom    top →
#
#         evolution       │      ]
#         of the stack    │      ]    }
#         as parsing      │      ]    }    >
#         progresses      │      ]    }
#                         v      ]

# FIXME:
# Try to move the 1st line down, then  up. The “no“ is merged, and we can't undo
# it.   Interesting:  if  you  decrease  the level  of  indentation,  the  issue
# disappears.
#
#                                              use ~/.vim/ftdetect/test.vim
#                                              no

# TODO: Disable folding while moving text, because moving text across folds is broken.

import Catch from 'lg.vim'

# Interface {{{1
def movesel#move(dir: string) #{{{2
# TODO: Make work with a motion?
# E.g.: `M-x }` moves the visual selection after the next paragraph.

    ResetSelection()

    if mode() == 'v'
        exe "norm! \<c-v>"
    endif
    var vmode = mode()

    if vmode == 'V'
        if ShouldUndojoin(vmode)
            undojoin | Lines(dir)
        else
            Lines(dir)
        endif
    elseif vmode == "\<c-v>"
        if ShouldUndojoin(vmode)
            undojoin | Block(dir)
        else
            Block(dir)
        endif
    endif
enddef

def movesel#duplicate(dir: string) #{{{2
    # Duplicates the selected lines/block of text
    var vmode = mode()
    ResetSelection()

    # Safe return if unsupported
    # TODO: Make this work in visual mode
    if vmode == 'v'
        # Give them back their selection
        ResetSelection()
    endif

    if vmode == 'V'
        if dir == 'up' || dir == 'down'
            DupLines(dir)
        else
            ResetSelection()
            echom 'Left and Right duplication not supported for lines'
        endif
    elseif vmode == "\<c-v>"
        DupBlock(dir)
    endif
enddef
#}}}1
# Core {{{1
def Lines(dir: string) #{{{2
    # Logic for moving text selected with visual line mode

    # build normal command string to reselect the VisualLine area
    var line1: number
    var line2: number
    [line1, line2] = [line("'<"), line("'>")]

    if dir == 'up' #{{{
        # First lines of file, move everything else down
        if line1 == 1
            append(line2, '')
            ResetSelection()
        else
            sil :*m'<-2
            norm! gv
        endif #}}}
    elseif dir == 'down' #{{{
        if line2 == line('$') # Moving down past EOF
            append(line1 - 1, '')
            ResetSelection()
        else
            sil :*m'>+1
            norm! gv
        endif #}}}
    elseif dir == 'right' #{{{
        for linenum in range(line1, line2)
            var line = getline(linenum)
            # Only insert space if the line is not empty
            if match(line, '^$') == -1
                setline(linenum, ' ' .. line)
            endif
        endfor
        ResetSelection() #}}}
    elseif dir == 'left' #{{{
        if getline(line1, line2)->match('^[^ \t]') == -1
            for linenum in range(line1, line2)
                getline(linenum)->substitute('^\s', '', '')->setline(linenum)
            endfor
        endif
        ResetSelection()
    endif #}}}
enddef

def Block(dir: string) #{{{2
    # Logic for moving  a visual block selection, this is  much more complicated
    # than lines  since I have to  be able to part  text in order to  insert the
    # incoming line.

    var ve_save = &l:ve
    try
        setl ve=all

        # While '< is always above or equal to '> in linenum, the column it
        # references could be the first or last col in the selected block
        var line1: number
        var fcol: number
        var foff: number
        var line2: number
        var lcol: number
        var loff: number
        var left_col: number
        var right_col: number
        var _: any
        [_, line1, fcol, foff] = getpos("'<")
        [_, line2, lcol, loff] = getpos("'>")
        [left_col, right_col] = sort([fcol + foff, lcol + loff], 'N')
        if &selection == 'exclusive' && fcol + foff < lcol + loff
            right_col -= 1
        endif

        if dir == 'up' #{{{
            if line1 == 1 # First lines of file
                append(0, '')
            endif
            norm! gvxkPgvkoko
            #}}}
        elseif dir == 'down' #{{{
            if line2 == line('$') # Moving down past EOF
                append('$', '')
            endif
            norm! gvxjPgvjojo
            #}}}
        elseif dir == 'right' #{{{
            var col1: number
            var col2: number
            [col1, col2] = sort([left_col, right_col], 'N')
            var old_width = (getline('.') .. '  ')
                ->matchstr('\%' .. col1 .. 'c.*\%' .. col2 .. 'c.')
                ->strchars(1)

            # Original code:
            #
            #     norm! gvxpgvlolo
            #             ^^
            # Why did we replace `xp` with `xlP`?{{{
            #
            # Try to  move a block  to the right, beyond  the end of  the lines,
            # while there  is a multibyte character  before the 1st line  of the
            # block (example: a bulleted list):
            #
            #    - hello
            #    - people
            #
            # It fails because of `xp`.
            #
            # Solution:
            #     xp → xlP
            #
            # Interesting:
            #
            # Set  've'   to  'all',   and  select   “hello“  in   a  visual
            # characterwise selection, then press `xp` (it will work):
            #
            #    - hello
            #
            # Reselect “hello“  in a  visual blockwise selection,  and press
            # `xp` (it will fail).
            # Now, reselect, and press `xlp`: it will also fail, but not because
            # it didn't move the block, but  because it moved it 1 character too
            # far.  Why?
            #}}}
            norm! gvxlPgvlolo

            # Problem:
            # Try to move the “join, delete, sort“ block to the right.
            # At one point, it misses a character (last `e` in `delete`).
            #
            #    - join
            #    - delete
            #    - sort
            #
            # Solution:
            # After reselecting  the text (`gv`),  check that the length  of the
            # block is the  same as before.  If it's shorter,  press `l` as many
            # times as necessary.

            [col1, col2] = [col("'<"), col("'>")]
            var new_width = getline('.')
                ->matchstr('\%' .. col1 .. 'c.*\%' .. col2 .. 'c.')
                ->strchars(1)
            if old_width > new_width
                exe 'norm! ' .. (old_width - new_width) .. 'l'
            endif
            #}}}
        elseif dir == 'left' #{{{
            var vcol1: number
            var vcol2: number
            [vcol1, vcol2] = sort([virtcol("'<"), virtcol("'>")], 'N')
            var old_width = (getline('.') .. '  ')
                ->matchstr('\%' .. vcol1 .. 'v.*\%' .. vcol2 .. 'v.')
                ->strchars(1)
            if left_col == 1
                exe "norm! gvA \e"
                if getline(line1, line2)->match('^\s') != -1
                    for linenum in range(line1, line2)
                        if getline(linenum)->match('^\s') != -1
                            getline(linenum)->substitute('^\s', '', '')->setline(linenum)
                            exe 'norm! ' .. linenum .. 'G' .. right_col .. "|a \e"
                        endif
                    endfor
                endif
                ResetSelection()
            else
                norm! gvxhPgvhoho
            endif
            # Problem:
            # Select “join“ and “delete“, then press `xhPgv`, it works.
            #
            #         -join
            #         -delete
            #
            # Now, repeat  the same commands;  this time, it will  fail, because
            # `gv` doesn't reselect the right area:
            #
            #         -join
            #         -delete
            #
            # As soon as the visual  selection cross the multibyte character, it
            # loses some characters.
            #
            # Solution:
            # After reselecting  the text (`gv`),  check that the length  of the
            # block is the  same as before.  If it's shorter,  press `h` as many
            # times as necessary.
            #
            # FIXME:
            # Try to move “join, delete, sort“ to the left:
            #     gvxhPgvhoho
            #
            #    - join
            #    - delete
            #    - sort

            var col1: number
            var col2: number
            [col1, col2] = [col("'<"), col("'>")]
            var new_width = getline('.')
                ->matchstr('\%' .. col1 .. 'c.*\%' .. col2 .. 'c.')
                ->strchars(1)
            if old_width > new_width
                exe 'norm! o' .. (old_width - new_width) .. 'ho'
            endif
        endif #}}}

        # Strip Whitespace
        # Need new positions since the visual area has moved
        [_, line1, fcol, foff] = getpos("'<")
        [_, line2, lcol, loff] = getpos("'>")
        [left_col, right_col] = sort([fcol + foff, lcol + loff], 'N')
        if &selection == 'exclusive' && fcol + foff < lcol + loff
            right_col -= 1
        endif
        for linenum in range(line1, line2)
            getline(linenum)->substitute('\s\+$', '', '')->setline(linenum)
        endfor
        # Take care of trailing space created on lines above or below while
        # moving past them
        if dir == 'up'
            getline(line2 + 1)->substitute('\s\+$', '', '')->setline(line2 + 1)
        elseif dir == 'down'
            getline(line1 - 1)->substitute('\s\+$', '', '')->setline(line1 - 1)
        endif
    catch
        Catch()
    finally
        &l:ve = ve_save
    endtry
enddef

def DupLines(dir: string) #{{{2
    var reselect: string
    if dir == 'up'
        reselect = 'gv'
    elseif dir == 'down'
        reselect = "'[V']"
    else
        ResetSelection()
        return
    endif

    exe 'norm! gvyP' .. reselect
enddef

def DupBlock(dir: string) #{{{2
    var ve_save = &l:ve
    try
        setl ve=all
        var line1: number
        var fcol: number
        var foff: number
        var line2: number
        var lcol: number
        var loff: number
        var left_col: number
        var right_col: number
        var _: any
        [_, line1, fcol, foff] = getpos("'<")
        [_, line2, lcol, loff] = getpos("'>")
        [left_col, right_col] = sort([fcol + foff, lcol + loff], {i, j -> i - j})
        if &selection == 'exclusive' && fcol + foff < lcol + loff
            right_col -= 1
        endif
        var numlines = (line2 - line1) + 1
        var numcols = (right_col - left_col)

        if dir == 'up'
            if (line1 - numlines) < 1
                # Insert enough lines to duplicate above
                for i in range((numlines - line1) + 1)
                    append(0, '')
                endfor
                # Position of selection has changed
                [_, line1, fcol, foff] = getpos("'<")
            endif

            var set_cursor = "\<cmd>call getpos(\"'<\")[1:3]->cursor()\r" .. numlines .. 'k'
            exe 'norm! gvy' .. set_cursor .. 'Pgv'

        elseif dir == 'down'
            if line2 + numlines >= line('$')
                for i in ((line2 + numlines) - line('$'))->range()
                    append('$', '')
                endfor
            endif
            exe "norm! gvy'>j" .. left_col .. '|Pgv'
        elseif dir == 'left'
            if numcols > 0
                exe 'norm! gvyP' .. numcols .. "l\<c-v>"
                    .. (numcols + (&selection == 'exclusive' ? 1 : 0)) .. 'l'
                    .. (numlines - 1) .. 'jo'
            else
                exe "norm! gvyP\<c-v>" .. (numlines - 1) .. 'jo'
            endif
        elseif dir == 'right'
            norm! gvyPgv
        else
            ResetSelection()
        endif
    catch
        Catch()
    finally
        &l:ve = ve_save
    endtry
enddef
#}}}1
# Util {{{1
def ResetSelection() #{{{2
    exe "norm! \egv"
enddef

def ShouldUndojoin(vmode: string): bool #{{{2
    if changenr() == undotree().seq_last
    && get(b:, '_movesel_state', {})->get('seq_last') == (changenr() - 1)
    && get(b:, '_movesel_state', {})->get('mode_last') == vmode
        return true
    endif

    b:_movesel_state = {mode_last: vmode, seq_last: undotree().seq_last}
    return false
enddef

