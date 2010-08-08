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

#include "libavcodec/vp8dsp.h"

void vp8_v_loop_filter16y_neon(uint8_t *dst, int stride,
        int flim_E, int flim_I, int hev_thresh);
void vp8_h_loop_filter16y_neon(uint8_t *dst, int stride,
        int flim_E, int flim_I, int hev_thresh);
void vp8_v_loop_filter8uv_neon(uint8_t *dstU, uint8_t *dstV, int stride,
        int flim_E, int flim_I, int hev_thresh);
void vp8_h_loop_filter8uv_neon(uint8_t *dstU, uint8_t *dstV, int stride,
        int flim_E, int flim_I, int hev_thresh);

void vp8_v_loop_filter16y_inner_neon(uint8_t *dst, int stride,
        int flim_E, int flim_I, int hev_thresh);
void vp8_h_loop_filter16y_inner_neon(uint8_t *dst, int stride,
        int flim_E, int flim_I, int hev_thresh);
void vp8_v_loop_filter8uv_inner_neon(uint8_t *dstU, uint8_t *dstV, int stride,
        int flim_E, int flim_I, int hev_thresh);
void vp8_h_loop_filter8uv_inner_neon(uint8_t *dstU, uint8_t *dstV, int stride,
        int flim_E, int flim_I, int hev_thresh);

void vp8_v_loop_filter_simple_neon(uint8_t *dst, int stride, int flim);
void vp8_h_loop_filter_simple_neon(uint8_t *dst, int stride, int flim);


av_cold void ff_vp8dsp_init_arm(VP8DSPContext *dsp)
{
    if (HAVE_NEON) {
        dsp->vp8_v_loop_filter16y = vp8_v_loop_filter16y_neon;
        dsp->vp8_h_loop_filter16y = vp8_h_loop_filter16y_neon;
        dsp->vp8_v_loop_filter8uv = vp8_v_loop_filter8uv_neon;
        dsp->vp8_h_loop_filter8uv = vp8_h_loop_filter8uv_neon;

        dsp->vp8_v_loop_filter16y_inner = vp8_v_loop_filter16y_inner_neon;
        dsp->vp8_h_loop_filter16y_inner = vp8_h_loop_filter16y_inner_neon;
        dsp->vp8_v_loop_filter8uv_inner = vp8_v_loop_filter8uv_inner_neon;
        dsp->vp8_h_loop_filter8uv_inner = vp8_h_loop_filter8uv_inner_neon;

#if 0
        dsp->vp8_v_loop_filter_simple = vp8_v_loop_filter_simple_neon;
        dsp->vp8_h_loop_filter_simple = vp8_h_loop_filter_simple_neon;
#endif
    }
}
