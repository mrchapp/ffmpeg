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

void vp8_idct_dc_add_neon(uint8_t * dst, DCTELEM block[16], int stride);
void vp8_idct_dc_add4uv_neon(uint8_t * dst, DCTELEM block[4][16], int stride);
void vp8_idct_dc_add4y_neon(uint8_t * dst, DCTELEM block[4][16], int stride);

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


/*
 * put_vp8_*_pixels_tab functions:
 */
void put_vp8_pixels16_neon(uint8_t *dst, int dststride, uint8_t *src,
        int srcstride, int h, int x, int y);
void put_vp8_pixels8_neon(uint8_t *dst, int dststride, uint8_t *src,
        int srcstride, int h, int x, int y);
void put_vp8_pixels4_neon(uint8_t *dst, int dststride, uint8_t *src,
        int srcstride, int h, int x, int y);
void put_vp8_epel16_v6_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel16_h6_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel16_h6v6_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_v6_neon (uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_h6_neon (uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_h6v6_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_v4_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_h4_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_h4v4_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_h6v4_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);
void put_vp8_epel8_h4v6_neon(uint8_t * dst, int dststride, uint8_t * src,
        int srcstride, int h, int mx, int my);

#define VP8_MC_FUNC(IDX, SIZE) \
    dsp->put_vp8_epel_pixels_tab[IDX][0][0] = put_vp8_pixels ## SIZE ## _neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][0][1] = put_vp8_epel ## SIZE ## _h4_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][0][2] = put_vp8_epel ## SIZE ## _h6_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][1][0] = put_vp8_epel ## SIZE ## _v4_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][1][1] = put_vp8_epel ## SIZE ## _h4v4_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][1][2] = put_vp8_epel ## SIZE ## _h6v4_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][2][0] = put_vp8_epel ## SIZE ## _v6_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][2][1] = put_vp8_epel ## SIZE ## _h4v6_neon; \
//    dsp->put_vp8_epel_pixels_tab[IDX][2][2] = put_vp8_epel ## SIZE ## _h6v6_neon

#define VP8_BILINEAR_MC_FUNC(IDX, SIZE) \
    dsp->put_vp8_bilinear_pixels_tab[IDX][0][0] = put_vp8_pixels ## SIZE ## _neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][0][1] = put_vp8_bilinear ## SIZE ## _h_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][0][2] = put_vp8_bilinear ## SIZE ## _h_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][1][0] = put_vp8_bilinear ## SIZE ## _v_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][1][1] = put_vp8_bilinear ## SIZE ## _hv_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][1][2] = put_vp8_bilinear ## SIZE ## _hv_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][2][0] = put_vp8_bilinear ## SIZE ## _v_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][2][1] = put_vp8_bilinear ## SIZE ## _hv_neon; \
//    dsp->put_vp8_bilinear_pixels_tab[IDX][2][2] = put_vp8_bilinear ## SIZE ## _hv_neon


av_cold void ff_vp8dsp_init_arm(VP8DSPContext *dsp)
{
    if (HAVE_NEON) {
        dsp->vp8_idct_dc_add = vp8_idct_dc_add_neon;
        dsp->vp8_idct_dc_add4y = vp8_idct_dc_add4y_neon;
        dsp->vp8_idct_dc_add4uv = vp8_idct_dc_add4uv_neon;

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

        VP8_MC_FUNC(0, 16);
        VP8_MC_FUNC(1, 8);
        VP8_MC_FUNC(2, 4);

        VP8_BILINEAR_MC_FUNC(0, 16);
        VP8_BILINEAR_MC_FUNC(1, 8);
        VP8_BILINEAR_MC_FUNC(2, 4);

        // XXX
        dsp->put_vp8_epel_pixels_tab[0][2][0] = put_vp8_epel16_v6_neon;
        dsp->put_vp8_epel_pixels_tab[0][0][2] = put_vp8_epel16_h6_neon;
        dsp->put_vp8_epel_pixels_tab[0][2][2] = put_vp8_epel16_h6v6_neon;
        dsp->put_vp8_epel_pixels_tab[1][2][0] = put_vp8_epel8_v6_neon;
        dsp->put_vp8_epel_pixels_tab[1][0][2] = put_vp8_epel8_h6_neon;
        dsp->put_vp8_epel_pixels_tab[1][2][2] = put_vp8_epel8_h6v6_neon;
        dsp->put_vp8_epel_pixels_tab[1][1][0] = put_vp8_epel8_v4_neon;
        dsp->put_vp8_epel_pixels_tab[1][0][1] = put_vp8_epel8_h4_neon;
        dsp->put_vp8_epel_pixels_tab[1][1][1] = put_vp8_epel8_h4v4_neon;
        dsp->put_vp8_epel_pixels_tab[1][1][2] = put_vp8_epel8_h6v4_neon;
        dsp->put_vp8_epel_pixels_tab[1][2][1] = put_vp8_epel8_h4v6_neon;
    }
}
