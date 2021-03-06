/**
 * VP8 compatible video decoder
 *
 * Copyright (C) 2010 Rob Clark <rob@ti.com>
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */


#include "asm.S"

/* NOTE: right now I'm assuming I can use all NEON registers.. which isn't quite
 * safe.. but as long as the rest of the C code in the decoder is not using float
 * (for which compiler might generate VFP instructions) or autovectorization, it
 * could be made to be safe using a similar trick to what libvpx does... see
 * vp8_push_neon() / vp8_pop_neon()
 */

/**
 * E - limit at the macroblock edge
 * I - limit for interior difference
 */

@ Register layout:
@   P3..Q3 -> q0..q7
@   flim_E -> q14
@   flim_I -> q15
@   hev_thresh -> r12 (ip)
@
@ TODO: maybe split this into parts so some can be shared by other lf
@ functions?
@
.macro  vp8_loop_filter, inner=0
        @ calculate hev and normal_limit:
        vabd.u8         q12, q2,  q3            @ abs(P1-P0)
        vabd.u8         q13, q5,  q4            @ abs(Q1-Q0)
        vcle.u8         q8,  q12, q15           @ abs(P1-P0) <= flim_I
        vcle.u8         q9,  q13, q15           @ abs(Q1-Q0) <= flim_I
        vabd.u8         q10, q0,  q1            @ abs(P3-P2)
        vabd.u8         q11, q1,  q2            @ abs(P2-P1)
        vand            q8,  q8,  q9
        vcle.u8         q10, q10, q15           @ abs(P3-P2) <= flim_I
        vcle.u8         q11, q11, q15           @ abs(P2-P1) <= flim_I
        vand            q8,  q8,  q10
        vand            q8,  q8,  q11
        vabd.u8         q10, q7,  q6            @ abs(Q3-Q2)
        vabd.u8         q11, q6,  q5            @ abs(Q2-Q1)
        vcle.u8         q10, q10, q15           @ abs(Q3-Q2) <= flim_I
        vcle.u8         q11, q11, q15           @ abs(Q2-Q1) <= flim_I
        vand            q8,  q8,  q10
        vand            q8,  q8,  q11
        vabd.u8         q9,  q3,  q4            @ abs(P0-Q0)
        vabd.u8         q10, q2,  q5            @ abs(P1-Q1)
        vqadd.u8        q9,  q9,  q9            @ abs(P0-Q0) * 2
        vshr.u8         q10, q10, #1            @ abs(P1-Q1) / 2
        vqadd.u8        q11, q9,  q10           @ (abs(P0-Q0)*2) + (abs(P1-Q1)/2)
        vcle.u8         q11, q11, q14           @ (abs(P0-Q0)*2) + (abs(P1-Q1)/2) <= flim_E
        vdup.8          q15, r12                @ hev_thresh
        vand            q8,  q8,  q11
        vcgt.u8         q12, q12, q15           @ abs(P1-P0) > hev_thresh
        vcgt.u8         q13, q13, q15           @ abs(Q1-Q0) > hev_thresh
        vorr            q9,  q12, q13

        vmov.i8         q13, #0x80

        @ at this point:
        @   q8: normal_limit
        @   q9: hev

        @ convert to signed value:
    .if ! \inner
        veor            q1,  q1,  q13           @ PS2 = P2 ^ 0x80
    .endif
        veor            q2,  q2,  q13           @ PS1 = P1 ^ 0x80
        veor            q3,  q3,  q13           @ PS0 = P0 ^ 0x80
        veor            q4,  q4,  q13           @ QS0 = Q0 ^ 0x80
        veor            q5,  q5,  q13           @ QS1 = Q1 ^ 0x80
    .if ! \inner
        veor            q6,  q6,  q13           @ QS2 = Q2 ^ 0x80
    .endif

        vmov.i16        q12, #3
        vsubl.s8        q10, d8,  d6            @ QS0 - PS0
        vsubl.s8        q11, d9,  d7            @   (widened to 16bit)
        vmul.i16        q10, q10, q12           @ w = 3 * (QS0 - PS0)
        vmul.i16        q11, q11, q12

        vmov.i8         q14, #4
        vmov.i8         q15, #3

        vqsub.s8        q12, q2,  q5            @ clamp(PS1-QS1)
    .if \inner
        vand            q12, q12, q9            @ if(hev) w += clamp(PS1-QS1)
    .endif
        vaddw.s8        q10, q10, d24           @ w += clamp(PS1-QS1)
        vaddw.s8        q11, q11, d25
        vqmovn.s16      d20, q10                @ narrow result back into q10
        vqmovn.s16      d21, q11
        vand            q10, q10, q8            @ w &= normal_limit

        @ registers used at this point..
        @   q0 -> P3  (don't corrupt)
        @   q1-q6 -> PS2-QS2
        @   q7 -> Q3  (don't corrupt)
        @   q9 -> hev
        @   q10 -> w
        @   q13 -> #0x80
        @   q14 -> #4
        @   q15 -> #3
        @   q8, q11, q12 -> unused

        @ filter_common:   is4tap==1
        @   c1 = clamp(w + 4) >> 3;
        @   c2 = clamp(w + 3) >> 3;
        @   Q0 = s2u(QS0 - c1);
        @   P0 = s2u(PS0 + c2);
    .if \inner
        @ filter_common is unconditional in inner blocks
        vmov            q12, q10
    .else
        vand            q12, q10, q9            @ w & hev
    .endif
        vqadd.s8        q11, q12, q14           @ c1 = clamp((w&hev)+4)
        vqadd.s8        q12, q12, q15           @ c2 = clamp((w&hev)+3)
        vshr.s8         q11, q11, #3            @ c1 >>= 3
        vshr.s8         q12, q12, #3            @ c2 >>= 3
        vqsub.s8        q4,  q4,  q11           @ QS0 = clamp(QS0-c1)
        vqadd.s8        q3,  q3,  q12           @ PS0 = clamp(PS0+c2)

    .if \inner
        @ the !is4tap case of filter_common, only used for inner blocks
        @   c3 = ((c1&~hev) + 1) >> 1;
        @   Q1 = s2u(QS1 - c3);
        @   P1 = s2u(PS1 + c3);
        vbic            q11, q11, q9            @ c1 & ~hev
        vmov.i8         q15, #1
        vadd.s8         q11, q11, q15           @ c3 = ((c1&~hev) + 1)
        vshr.s8         q11, q11, #1            @ c3 >>= 1
        vqsub.s8        q5,  q5,  q11           @ QS1 = clamp(QS1-c3)
        vqadd.s8        q2,  q2,  q11           @ PS1 = clamp(PS1+c3)
    .else

        @ filter_mbedge:
        @   a = clamp((27*w + 63) >> 7);
        @   Q0 = s2u(QS0 - a);
        @   P0 = s2u(PS0 + a);
        vmov.i16        q14, #63
        vbic            q10, q10, q9            @ w &= ~hev
        vmov.i8         d30, #27
        vmov            q11, q14
        vmov            q12, q14
        vmlal.s8        q11, d20, d30           @ 27*w + 63
        vmlal.s8        q12, d21, d30
        vqshrn.s16      d22, q11, #7            @ a = clamp((27*w + 63)>>7)
        vqshrn.s16      d23, q12, #7
        vqsub.s8        q4,  q4,  q11           @ QS0 = clamp(QS0-a)
        vqadd.s8        q3,  q3,  q11           @ PS0 = clamp(PS0+a)
        @   a = clamp((18*w + 63) >> 7);
        @   Q1 = s2u(QS1 - a);
        @   P1 = s2u(PS1 + a);
        vmov.i8         d30, #18
        vmov            q11, q14
        vmov            q12, q14
        vmlal.s8        q11, d20, d30           @ 18*w + 63
        vmlal.s8        q12, d21, d30
        vqshrn.s16      d22, q11, #7            @ a = clamp((18*w + 63)>>7)
        vqshrn.s16      d23, q12, #7
        vqsub.s8        q5,  q5,  q11           @ QS1 = clamp(QS1-a)
        vqadd.s8        q2,  q2,  q11           @ PS1 = clamp(PS1+a)
        @   a = clamp((9*w + 63) >> 7);
        @   Q2 = s2u(QS2 - a);
        @   P2 = s2u(PS2 + a);
        vmov.i8         d30, #9
        vmov            q11, q14
        vmlal.s8        q11, d20, d30           @ 9*w + 63
        vmlal.s8        q14, d21, d30
        vqshrn.s16      d22, q11, #7            @ a = clamp((9*w + 63)>>7)
        vqshrn.s16      d23, q14, #7
        vqsub.s8        q6,  q6,  q11           @ QS2 = clamp(QS2-a)
        vqadd.s8        q1,  q1,  q11           @ PS2 = clamp(PS2+a)
    .endif

        @ convert back to unsigned value:
    .if ! \inner
        veor            q1,  q1,  q13           @ P2 = PS2 ^ 0x80
    .endif
        veor            q2,  q2,  q13           @ P1 = PS1 ^ 0x80
        veor            q3,  q3,  q13           @ P0 = PS0 ^ 0x80
        veor            q4,  q4,  q13           @ Q0 = QS0 ^ 0x80
        veor            q5,  q5,  q13           @ Q1 = QS1 ^ 0x80
    .if ! \inner
        veor            q6,  q6,  q13           @ Q2 = QS2 ^ 0x80
    .endif
.endm

@ macro to transpose q0..q7 for h filter variants
.macro transpose8x16matrix
        vtrn.32         q0,   q4
        vtrn.32         q1,   q5
        vtrn.32         q2,   q6
        vtrn.32         q3,   q7

        vtrn.16         q0,   q2
        vtrn.16         q1,   q3
        vtrn.16         q4,   q6
        vtrn.16         q5,   q7

        vtrn.8          q0,   q1
        vtrn.8          q2,   q3
        vtrn.8          q4,   q5
        vtrn.8          q6,   q7
.endm

@ Filter top edge:
@
@void vp8_v_loop_filter16y_neon(uint8_t *dst, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_v_loop_filter16y_neon, export=1
        sub             r0,  r0,  r1,  lsl #2   @ subtract 4 rows
        ldr             r12, [sp, #0]           @ load hev_thresh from stack

        @ Load pixels:
        vld1.8          {q0},     [r0], r1      @ P3
        vld1.8          {q1},     [r0], r1      @ P2
        vld1.8          {q2},     [r0], r1      @ P1
        vld1.8          {q3},     [r0], r1      @ P0
        vld1.8          {q4},     [r0], r1      @ Q0
        vld1.8          {q5},     [r0], r1      @ Q1
        vld1.8          {q6},     [r0], r1      @ Q2
        vld1.8          {q7},     [r0]          @ Q3

        vdup.8          q14, r2                 @ flim_E
        vdup.8          q15, r3                 @ flim_I

        vp8_loop_filter

        @ back up to P2:  dst -= stride * 6
        sub             r0,  r0,  r1,  lsl #2
        sub             r0,  r0,  r1,  lsl #1

        @ Store pixels:
        vst1.8          {q1},     [r0], r1      @ P2
        vst1.8          {q2},     [r0], r1      @ P1
        vst1.8          {q3},     [r0], r1      @ P0
        vst1.8          {q4},     [r0], r1      @ Q0
        vst1.8          {q5},     [r0], r1      @ Q1
        vst1.8          {q6},     [r0]          @ Q2

        bx              lr
endfunc
@}

@void vp8_v_loop_filter16y_inner_neon(uint8_t *dst, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_v_loop_filter16y_inner_neon, export=1
        sub             r0,  r0,  r1,  lsl #2   @ subtract 4 rows
        ldr             r12, [sp, #0]           @ load hev_thresh from stack

        @ Load pixels:
        vld1.8          {q0},     [r0], r1      @ P3
        vld1.8          {q1},     [r0], r1      @ P2
        vld1.8          {q2},     [r0], r1      @ P1
        vld1.8          {q3},     [r0], r1      @ P0
        vld1.8          {q4},     [r0], r1      @ Q0
        vld1.8          {q5},     [r0], r1      @ Q1
        vld1.8          {q6},     [r0], r1      @ Q2
        vld1.8          {q7},     [r0]          @ Q3

        vdup.8          q14, r2                 @ flim_E
        vdup.8          q15, r3                 @ flim_I

        vp8_loop_filter, inner=1

        @ back up to P2:  dst -= stride * 6
        sub             r0,  r0,  r1,  lsl #2
        sub             r0,  r0,  r1,  lsl #1

        @ Store pixels:
        vst1.8          {q1},     [r0], r1      @ P2
        vst1.8          {q2},     [r0], r1      @ P1
        vst1.8          {q3},     [r0], r1      @ P0
        vst1.8          {q4},     [r0], r1      @ Q0
        vst1.8          {q5},     [r0], r1      @ Q1
        vst1.8          {q6},     [r0]          @ Q2

        bx              lr
endfunc
@}

@void vp8_v_loop_filter8uv_neon(uint8_t *dstU, uint8_t *dstV, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_v_loop_filter8uv_neon, export=1
        sub             r0,  r0,  r2,  lsl #2   @ subtract 4 rows from u
        sub             r1,  r1,  r2,  lsl #2   @ subtract 4 rows from v
        ldr             r12, [sp, #0]           @ load flim_I from stack

        @ Load pixels:
        vld1.8          {d0},     [r0], r2      @ P3
        vld1.8          {d1},     [r1], r2      @ P3
        vld1.8          {d2},     [r0], r2      @ P2
        vld1.8          {d3},     [r1], r2      @ P2
        vld1.8          {d4},     [r0], r2      @ P1
        vld1.8          {d5},     [r1], r2      @ P1
        vld1.8          {d6},     [r0], r2      @ P0
        vld1.8          {d7},     [r1], r2      @ P0
        vld1.8          {d8},     [r0], r2      @ Q0
        vld1.8          {d9},     [r1], r2      @ Q0
        vld1.8          {d10},    [r0], r2      @ Q1
        vld1.8          {d11},    [r1], r2      @ Q1
        vld1.8          {d12},    [r0], r2      @ Q2
        vld1.8          {d13},    [r1], r2      @ Q2
        vld1.8          {d14},    [r0]          @ Q3
        vld1.8          {d15},    [r1]          @ Q3

        vdup.8          q14, r3                 @ flim_E
        vdup.8          q15, r12                @ flim_I
        ldr             r12, [sp, #4]           @ hev_thresh

        vp8_loop_filter

        @ back up to P2:  u -= stride * 6
        sub             r0,  r0,  r2,  lsl #2
        sub             r0,  r0,  r2,  lsl #1

        @ back up to P2:  v -= stride * 6
        sub             r1,  r1,  r2,  lsl #2
        sub             r1,  r1,  r2,  lsl #1

        @ Store pixels:
        vst1.8          {d2},     [r0], r2      @ P2
        vst1.8          {d3},     [r1], r2      @ P2
        vst1.8          {d4},     [r0], r2      @ P1
        vst1.8          {d5},     [r1], r2      @ P1
        vst1.8          {d6},     [r0], r2      @ P0
        vst1.8          {d7},     [r1], r2      @ P0
        vst1.8          {d8},     [r0], r2      @ Q0
        vst1.8          {d9},     [r1], r2      @ Q0
        vst1.8          {d10},    [r0], r2      @ Q1
        vst1.8          {d11},    [r1], r2      @ Q1
        vst1.8          {d12},    [r0]          @ Q2
        vst1.8          {d13},    [r1]          @ Q2

        bx              lr
endfunc
@}

@void vp8_v_loop_filter8uv_inner_neon(uint8_t *dstU, uint8_t *dstV, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_v_loop_filter8uv_inner_neon, export=1
        sub             r0,  r0,  r2,  lsl #2   @ subtract 4 rows from u
        sub             r1,  r1,  r2,  lsl #2   @ subtract 4 rows from v
        ldr             r12, [sp, #0]           @ load flim_I from stack

        @ Load pixels:
        vld1.8          {d0},     [r0], r2      @ P3
        vld1.8          {d1},     [r1], r2      @ P3
        vld1.8          {d2},     [r0], r2      @ P2
        vld1.8          {d3},     [r1], r2      @ P2
        vld1.8          {d4},     [r0], r2      @ P1
        vld1.8          {d5},     [r1], r2      @ P1
        vld1.8          {d6},     [r0], r2      @ P0
        vld1.8          {d7},     [r1], r2      @ P0
        vld1.8          {d8},     [r0], r2      @ Q0
        vld1.8          {d9},     [r1], r2      @ Q0
        vld1.8          {d10},    [r0], r2      @ Q1
        vld1.8          {d11},    [r1], r2      @ Q1
        vld1.8          {d12},    [r0], r2      @ Q2
        vld1.8          {d13},    [r1], r2      @ Q2
        vld1.8          {d14},    [r0]          @ Q3
        vld1.8          {d15},    [r1]          @ Q3

        vdup.8          q14, r3                 @ flim_E
        vdup.8          q15, r12                @ flim_I
        ldr             r12, [sp, #4]           @ hev_thresh

        vp8_loop_filter, inner=1

        @ back up to P2:  u -= stride * 6
        sub             r0,  r0,  r2,  lsl #2
        sub             r0,  r0,  r2,  lsl #1

        @ back up to P2:  v -= stride * 6
        sub             r1,  r1,  r2,  lsl #2
        sub             r1,  r1,  r2,  lsl #1

        @ Store pixels:
        vst1.8          {d2},     [r0], r2      @ P2
        vst1.8          {d3},     [r1], r2      @ P2
        vst1.8          {d4},     [r0], r2      @ P1
        vst1.8          {d5},     [r1], r2      @ P1
        vst1.8          {d6},     [r0], r2      @ P0
        vst1.8          {d7},     [r1], r2      @ P0
        vst1.8          {d8},     [r0], r2      @ Q0
        vst1.8          {d9},     [r1], r2      @ Q0
        vst1.8          {d10},    [r0], r2      @ Q1
        vst1.8          {d11},    [r1], r2      @ Q1
        vst1.8          {d12},    [r0]          @ Q2
        vst1.8          {d13},    [r1]          @ Q2

        bx              lr
endfunc
@}

@void vp8_v_loop_filter_simple_neon(uint8_t *dst, int stride, int flim)
@{
@}

@ Filter left edge:
@
@void vp8_h_loop_filter16y_neon(uint8_t *dst, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_h_loop_filter16y_neon, export=1
        sub             r0,  r0,  #4            @ subtract 4 cols
        ldr             r12, [sp, #0]           @ load hev_thresh from stack

        @ Load pixels:
        vld1.8          {d0},     [r0], r1      @ load first 8-line src data
        vld1.8          {d2},     [r0], r1
        vld1.8          {d4},     [r0], r1
        vld1.8          {d6},     [r0], r1
        vld1.8          {d8},     [r0], r1
        vld1.8          {d10},    [r0], r1
        vld1.8          {d12},    [r0], r1
        vld1.8          {d14},    [r0], r1
        vld1.8          {d1},     [r0], r1      @ load second 8-line src data
        vld1.8          {d3},     [r0], r1
        vld1.8          {d5},     [r0], r1
        vld1.8          {d7},     [r0], r1
        vld1.8          {d9},     [r0], r1
        vld1.8          {d11},    [r0], r1
        vld1.8          {d13},    [r0], r1
        vld1.8          {d15},    [r0], r1

        transpose8x16matrix

        vdup.8          q14, r2                 @ flim_E
        vdup.8          q15, r3                 @ flim_I

        vp8_loop_filter

        sub             r0,  r0,  r1, lsl #4    @ backup 16 rows

        transpose8x16matrix

        @ Store pixels:
        vst1.8          {d0},     [r0],     r1
        vst1.8          {d2},     [r0],     r1
        vst1.8          {d4},     [r0],     r1
        vst1.8          {d6},     [r0],     r1
        vst1.8          {d8},     [r0],     r1
        vst1.8          {d10},    [r0],     r1
        vst1.8          {d12},    [r0],     r1
        vst1.8          {d14},    [r0],     r1
        vst1.8          {d1},     [r0],     r1
        vst1.8          {d3},     [r0],     r1
        vst1.8          {d5},     [r0],     r1
        vst1.8          {d7},     [r0],     r1
        vst1.8          {d9},     [r0],     r1
        vst1.8          {d11},    [r0],     r1
        vst1.8          {d13},    [r0],     r1
        vst1.8          {d15},    [r0]

        bx              lr
endfunc
@}

@void vp8_h_loop_filter16y_inner_neon(uint8_t *dst, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_h_loop_filter16y_inner_neon, export=1
        sub             r0,  r0,  #4            @ subtract 4 cols
        ldr             r12, [sp, #0]           @ load hev_thresh from stack

        @ Load pixels:
        vld1.8          {d0},     [r0], r1      @ load first 8-line src data
        vld1.8          {d2},     [r0], r1
        vld1.8          {d4},     [r0], r1
        vld1.8          {d6},     [r0], r1
        vld1.8          {d8},     [r0], r1
        vld1.8          {d10},    [r0], r1
        vld1.8          {d12},    [r0], r1
        vld1.8          {d14},    [r0], r1
        vld1.8          {d1},     [r0], r1      @ load second 8-line src data
        vld1.8          {d3},     [r0], r1
        vld1.8          {d5},     [r0], r1
        vld1.8          {d7},     [r0], r1
        vld1.8          {d9},     [r0], r1
        vld1.8          {d11},    [r0], r1
        vld1.8          {d13},    [r0], r1
        vld1.8          {d15},    [r0], r1

        transpose8x16matrix

        vdup.8          q14, r2                 @ flim_E
        vdup.8          q15, r3                 @ flim_I

        vp8_loop_filter, inner=1

        sub             r0,  r0,  r1, lsl #4    @ backup 16 rows

        transpose8x16matrix

        @ Store pixels:
        vst1.8          {d0},     [r0],     r1
        vst1.8          {d2},     [r0],     r1
        vst1.8          {d4},     [r0],     r1
        vst1.8          {d6},     [r0],     r1
        vst1.8          {d8},     [r0],     r1
        vst1.8          {d10},    [r0],     r1
        vst1.8          {d12},    [r0],     r1
        vst1.8          {d14},    [r0],     r1
        vst1.8          {d1},     [r0],     r1
        vst1.8          {d3},     [r0],     r1
        vst1.8          {d5},     [r0],     r1
        vst1.8          {d7},     [r0],     r1
        vst1.8          {d9},     [r0],     r1
        vst1.8          {d11},    [r0],     r1
        vst1.8          {d13},    [r0],     r1
        vst1.8          {d15},    [r0]

        bx              lr
endfunc
@}

@void vp8_h_loop_filter8uv_neon(uint8_t *dstU, uint8_t *dstV, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_h_loop_filter8uv_neon, export=1
        sub             r0,  r0,  #4            @ subtract 4 cols from u
        sub             r1,  r1,  #4            @ subtract 4 rows from v
        ldr             r12, [sp, #0]           @ load flim_I from stack

        @ Load pixels:
        vld1.8          {d0},     [r0], r2      @ load u
        vld1.8          {d1},     [r1], r2      @ load v
        vld1.8          {d2},     [r0], r2
        vld1.8          {d3},     [r1], r2
        vld1.8          {d4},     [r0], r2
        vld1.8          {d5},     [r1], r2
        vld1.8          {d6},     [r0], r2
        vld1.8          {d7},     [r1], r2
        vld1.8          {d8},     [r0], r2
        vld1.8          {d9},     [r1], r2
        vld1.8          {d10},    [r0], r2
        vld1.8          {d11},    [r1], r2
        vld1.8          {d12},    [r0], r2
        vld1.8          {d13},    [r1], r2
        vld1.8          {d14},    [r0], r2
        vld1.8          {d15},    [r1], r2

        transpose8x16matrix

        vdup.8          q14, r3                 @ flim_E
        vdup.8          q15, r12                @ flim_I
        ldr             r12, [sp, #4]           @ hev_thresh

        vp8_loop_filter

        sub             r0,  r0,  r2, lsl #3    @ backup u 8 rows
        sub             r1,  r1,  r2, lsl #3    @ backup v 8 rows

        transpose8x16matrix

        @ Store pixels:
        vst1.8          {d0},     [r0], r2
        vst1.8          {d1},     [r1], r2
        vst1.8          {d2},     [r0], r2
        vst1.8          {d3},     [r1], r2
        vst1.8          {d4},     [r0], r2
        vst1.8          {d5},     [r1], r2
        vst1.8          {d6},     [r0], r2
        vst1.8          {d7},     [r1], r2
        vst1.8          {d8},     [r0], r2
        vst1.8          {d9},     [r1], r2
        vst1.8          {d10},    [r0], r2
        vst1.8          {d11},    [r1], r2
        vst1.8          {d12},    [r0], r2
        vst1.8          {d13},    [r1], r2
        vst1.8          {d14},    [r0]
        vst1.8          {d15},    [r1]

        bx              lr
endfunc
@}

@void vp8_h_loop_filter8uv_inner_neon(uint8_t *dstU, uint8_t *dstV, int stride,
@        int flim_E, int flim_I, int hev_thresh)
@{
function vp8_h_loop_filter8uv_inner_neon, export=1
        sub             r0,  r0,  #4            @ subtract 4 cols from u
        sub             r1,  r1,  #4            @ subtract 4 rows from v
        ldr             r12, [sp, #0]           @ load flim_I from stack

        @ Load pixels:
        vld1.8          {d0},     [r0], r2      @ load u
        vld1.8          {d1},     [r1], r2      @ load v
        vld1.8          {d2},     [r0], r2
        vld1.8          {d3},     [r1], r2
        vld1.8          {d4},     [r0], r2
        vld1.8          {d5},     [r1], r2
        vld1.8          {d6},     [r0], r2
        vld1.8          {d7},     [r1], r2
        vld1.8          {d8},     [r0], r2
        vld1.8          {d9},     [r1], r2
        vld1.8          {d10},    [r0], r2
        vld1.8          {d11},    [r1], r2
        vld1.8          {d12},    [r0], r2
        vld1.8          {d13},    [r1], r2
        vld1.8          {d14},    [r0], r2
        vld1.8          {d15},    [r1], r2

        transpose8x16matrix

        vdup.8          q14, r3                 @ flim_E
        vdup.8          q15, r12                @ flim_I
        ldr             r12, [sp, #4]           @ hev_thresh

        vp8_loop_filter, inner=1

        sub             r0,  r0,  r2, lsl #3    @ backup u 8 rows
        sub             r1,  r1,  r2, lsl #3    @ backup v 8 rows

        transpose8x16matrix

        @ Store pixels:
        vst1.8          {d0},     [r0], r2
        vst1.8          {d1},     [r1], r2
        vst1.8          {d2},     [r0], r2
        vst1.8          {d3},     [r1], r2
        vst1.8          {d4},     [r0], r2
        vst1.8          {d5},     [r1], r2
        vst1.8          {d6},     [r0], r2
        vst1.8          {d7},     [r1], r2
        vst1.8          {d8},     [r0], r2
        vst1.8          {d9},     [r1], r2
        vst1.8          {d10},    [r0], r2
        vst1.8          {d11},    [r1], r2
        vst1.8          {d12},    [r0], r2
        vst1.8          {d13},    [r1], r2
        vst1.8          {d14},    [r0]
        vst1.8          {d15},    [r1]

        bx              lr
endfunc
@}

@void vp8_h_loop_filter_simple_neon(uint8_t *dst, int stride, int flim)
@{
@}
