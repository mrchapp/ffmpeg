/*
 * Watermark Hook 
 * Copyright (c) 2005 Marcus Engene myfirstname(at)mylastname.se
 *
 * The watermarkpicture works like this. (Assuming colorintencities 0..0xff)
 * Per color do this:
 * If mask color is 0x80, no change to original frame.
 * If mask color is < 0x80 the abs difference is subtracted from frame. If
 * result < 0, result = 0
 * If mask color is > 0x80 the abs difference is added to frame. If result
 * > 0xff, result = 0xff
 *
 * This way a mask that is visible both in light pictures and in dark can be
 * made (fex by using a picture generated by gimp and the bump map tool). 
 *
 * An example watermark file is at
 * http://engene.se/ffmpeg_watermark.gif
 *
 * Example usage:
 *  ffmpeg -i infile -vhook '/path/watermark.so -f wm.gif' out.mov
 *
 * Note that the entire vhook argument is encapsulated in ''. This
 * way, arguments to the vhook won't be mixed up with those to ffmpeg.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

//#include <stdlib.h>
//#include <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
 
#include "common.h"
#include "avformat.h"

#include "framehook.h"

typedef struct {
    char            filename[2000];
    int             x_size;
    int             y_size;

    /* get_watermark_picture() variables */
    AVFormatContext *pFormatCtx;
    const char     *p_ext;
    int             videoStream;
    int             frameFinished;
    AVCodecContext *pCodecCtx;    
    AVCodec        *pCodec;    
    AVFrame        *pFrame;
    AVPacket        packet;
    int             numBytes;
    uint8_t        *buffer;
    int             i;
    AVInputFormat  *file_iformat;
    AVStream       *st;
    int             is_done;    
    AVFrame        *pFrameRGB;
} ContextInfo;

int get_watermark_picture(ContextInfo *ci, int cleanup);


/****************************************************************************
 * 
 ****************************************************************************/
void Release(void *ctx)
{
    ContextInfo *ci;
    ci = (ContextInfo *) ctx;

    if (ci) get_watermark_picture(ci, 1);
    
    if (ctx)
        av_free(ctx);
}


/****************************************************************************
 * 
 ****************************************************************************/
int Configure(void **ctxp, int argc, char *argv[])
{
    ContextInfo *ci;
    int c;

    if (0 == (*ctxp = av_mallocz(sizeof(ContextInfo)))) return -1;
    ci = (ContextInfo *) *ctxp;

    optind = 0;
    
    // Struct is mallocz:ed so no need to reset.
        
    while ((c = getopt(argc, argv, "f:")) > 0) {
        switch (c) {
            case 'f':
                strncpy(ci->filename, optarg, 1999);
                ci->filename[1999] = 0;
                break;
            default:
                av_log(NULL, AV_LOG_DEBUG, "Unrecognized argument '%s'\n", argv[optind]);
                return -1;
        }
    }
    
    //
    if (0 == ci->filename[0]) return -1;
        
    av_register_all();
    return get_watermark_picture(ci, 0);

    return 0;
}


/****************************************************************************
 * Why is this a void returning functions? I want to be able to go wrong!
 ****************************************************************************/
void Process(void *ctx, 
             AVPicture *picture, 
             enum PixelFormat pix_fmt, 
             int src_width, 
             int src_height, 
             int64_t pts)
{
    ContextInfo *ci = (ContextInfo *) ctx;
    char *buf = 0;
    AVPicture picture1;
    AVPicture *pict = picture;
    
    AVFrame *pFrameRGB;
    int xm_size;
    int ym_size;

//    int retval = -1;
    int x;
    int y;
    int offs, offsm;
    int mpoffs;
    uint32_t *p_pixel = 0;
    uint32_t pixel_meck;
    uint32_t pixel;
    uint32_t pixelm;
    int tmp;    
    
        
//??    (void) ci;

    if (pix_fmt != PIX_FMT_RGBA32) {
        int size;

        size = avpicture_get_size(PIX_FMT_RGBA32, src_width, src_height);
        buf = av_malloc(size);

        avpicture_fill(&picture1, buf, PIX_FMT_RGBA32, src_width, src_height);
        if (img_convert(&picture1, PIX_FMT_RGBA32, 
                        picture, pix_fmt, src_width, src_height) < 0) {
            av_free(buf);
            return;
        }
        pict = &picture1;
    }

    /* Insert filter code here */ /* ok */

    // Get me next frame    
    if (0 > get_watermark_picture(ci, 0)) {
        return;
    }     
    // These are the three original static variables in the ffmpeg hack.
    pFrameRGB = ci->pFrameRGB;
    xm_size = ci->x_size;
    ym_size = ci->y_size;
    
    // I'll do the *4 => <<2 crap later. Most compilers understand that anyway.
    // According to avcodec.h PIX_FMT_RGBA32 is handled in endian specific manner.
    for (y=0; y<src_height; y++) {
        offs = y * (src_width * 4);
        offsm = (((y * ym_size) / src_height) * 4) * xm_size; // offsm first in maskline. byteoffs!
        for (x=0; x<src_width; x++) {
            mpoffs = offsm + (((x * xm_size) / src_width) * 4);
            p_pixel = (uint32_t *)&((pFrameRGB->data[0])[mpoffs]);
            pixelm = *p_pixel;
            p_pixel = (uint32_t *)&((pict->data[0])[offs]);
            pixel = *p_pixel;
//          pixelm = *((uint32_t *)&(pFrameRGB->data[mpoffs]));
            pixel_meck = pixel & 0xff000000;

            // R
            tmp = (int)((pixel >> 16) & 0xff) + (int)((pixelm >> 16) & 0xff) - 0x80;
            if (tmp > 255) tmp = 255;
            if (tmp < 0) tmp = 0;
            pixel_meck |= (tmp << 16) & 0xff0000;
            // G
            tmp = (int)((pixel >> 8) & 0xff) + (int)((pixelm >> 8) & 0xff) - 0x80;
            if (tmp > 255) tmp = 255;
            if (tmp < 0) tmp = 0;
            pixel_meck |= (tmp << 8) & 0xff00;
            // B
            tmp = (int)((pixel >> 0) & 0xff) + (int)((pixelm >> 0) & 0xff) - 0x80;
            if (tmp > 255) tmp = 255;
            if (tmp < 0) tmp = 0;
            pixel_meck |= (tmp << 0) & 0xff;
            
            
            // test:
            //pixel_meck = pixel & 0xff000000;
            //pixel_meck |= (pixelm & 0x00ffffff);

            *p_pixel = pixel_meck;

            offs += 4; 
        } // foreach X
    } // foreach Y    
    
    
    

    if (pix_fmt != PIX_FMT_RGBA32) {
        if (img_convert(picture, pix_fmt, 
                        &picture1, PIX_FMT_RGBA32, src_width, src_height) < 0) {
        }
    }

    av_free(buf);
}


/****************************************************************************
 * When cleanup == 0, we try to get the next frame. If no next frame, nothing
 * is done.
 *
 * This code follows the example on 
 * http://www.inb.uni-luebeck.de/~boehme/using_libavcodec.html
 *
 * 0 = ok, -1 = error
 ****************************************************************************/
int get_watermark_picture(ContextInfo *ci, int cleanup)
{
    if (1 == ci->is_done && 0 == cleanup) return 0;

    // Yes, *pFrameRGB arguments must be null the first time otherwise it's not good..
    // This block is only executed the first time we enter this function.
    if (0 == ci->pFrameRGB && 
        0 == cleanup) 
    {
      
        /* 
         * The last three parameters specify the file format, buffer size and format
         * parameters; by simply specifying NULL or 0 we ask libavformat to auto-detect
         * the format and use a default buffer size. (Didn't work!)
         */
        if (av_open_input_file(&ci->pFormatCtx, ci->filename, NULL, 0, NULL) != 0) {

            // Martin says this should not be necessary but it failed for me sending in
            // NULL instead of file_iformat to av_open_input_file()
            ci->i = strlen(ci->filename);
            if (0 == ci->i) {
                av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() No filename to watermark vhook\n");
                return -1;
            }
            while (ci->i > 0) {
                if (ci->filename[ci->i] == '.') {
                    ci->i++;
                    break;
                }
                ci->i--;
            }
               ci->p_ext = &(ci->filename[ci->i]);
            ci->file_iformat = av_find_input_format (ci->p_ext);
            if (0 == ci->file_iformat) {
                av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Really failed to find iformat [%s]\n", ci->p_ext);
                return -1;
            }
            // now continues the Martin template.    
            
            if (av_open_input_file(&ci->pFormatCtx, ci->filename, ci->file_iformat, 0, NULL)!=0) {
                av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Failed to open input file [%s]\n", ci->filename);
                return -1;
            }            
        }
        
        /* 
         * This fills the streams field of the AVFormatContext with valid information.
         */
        if(av_find_stream_info(ci->pFormatCtx)<0) {
            av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Failed to find stream info\n");
            return -1;
        }
    
        /*
         * As mentioned in the introduction, we'll handle only video streams, not audio 
         * streams. To make things nice and easy, we simply use the first video stream we
         * find.
         */
        ci->videoStream=-1;
        for(ci->i = 0; ci->i < ci->pFormatCtx->nb_streams; ci->i++)
            if(ci->pFormatCtx->streams[ci->i]->codec.codec_type==CODEC_TYPE_VIDEO)
            {
                ci->videoStream = ci->i;
                break;
            }
        if(ci->videoStream == -1) {
            av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Failed to find any video stream\n");
            return -1;
        }
        
        ci->st = ci->pFormatCtx->streams[ci->videoStream];
        ci->x_size = ci->st->codec.width;
        ci->y_size = ci->st->codec.height;
        
        // Get a pointer to the codec context for the video stream
        ci->pCodecCtx = &ci->pFormatCtx->streams[ci->videoStream]->codec;
            
        
        /*
         * OK, so now we've got a pointer to the so-called codec context for our video
         * stream, but we still have to find the actual codec and open it.
         */    
        // Find the decoder for the video stream
        ci->pCodec = avcodec_find_decoder(ci->pCodecCtx->codec_id);
        if(ci->pCodec == NULL) {
            av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Failed to find any codec\n");
            return -1;
        }
        
        // Inform the codec that we can handle truncated bitstreams -- i.e.,
        // bitstreams where frame boundaries can fall in the middle of packets
        if (ci->pCodec->capabilities & CODEC_CAP_TRUNCATED)
            ci->pCodecCtx->flags|=CODEC_FLAG_TRUNCATED;
        
        // Open codec
        if(avcodec_open(ci->pCodecCtx, ci->pCodec)<0) {
            av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Failed to open codec\n");
            return -1;
        }
        
        // Hack to correct wrong frame rates that seem to be generated by some 
        // codecs
        if (ci->pCodecCtx->time_base.den>1000 && ci->pCodecCtx->time_base.num==1)
            ci->pCodecCtx->time_base.num=1000;    
    
        /*
         * Allocate a video frame to store the decoded images in.
         */
        ci->pFrame = avcodec_alloc_frame();
    
        
        /*
         * The RGB image pFrameRGB (of type AVFrame *) is allocated like this:
         */
        // Allocate an AVFrame structure
        ci->pFrameRGB=avcodec_alloc_frame();
        if(ci->pFrameRGB==NULL) {
            av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Failed to alloc pFrameRGB\n");
            return -1;
        }
        
        // Determine required buffer size and allocate buffer
        ci->numBytes = avpicture_get_size(PIX_FMT_RGBA32, ci->pCodecCtx->width,
            ci->pCodecCtx->height);
        ci->buffer = av_malloc(ci->numBytes);
        
        // Assign appropriate parts of buffer to image planes in pFrameRGB
        avpicture_fill((AVPicture *)ci->pFrameRGB, ci->buffer, PIX_FMT_RGBA32,
            ci->pCodecCtx->width, ci->pCodecCtx->height);    
    }
    // TODO loop, pingpong etc?
    if (0 == cleanup) 
    {    
//        av_log(NULL, AV_LOG_DEBUG, "get_watermark_picture() Get a frame\n");
        while(av_read_frame(ci->pFormatCtx, &ci->packet)>=0)
        {
            // Is this a packet from the video stream?
            if(ci->packet.stream_index == ci->videoStream)
            {
                // Decode video frame
                avcodec_decode_video(ci->pCodecCtx, ci->pFrame, &ci->frameFinished, 
                    ci->packet.data, ci->packet.size);
        
                // Did we get a video frame?
                if(ci->frameFinished)
                {
                    // Convert the image from its native format to RGBA32
                    img_convert((AVPicture *)ci->pFrameRGB, PIX_FMT_RGBA32, 
                        (AVPicture*)(ci->pFrame), ci->pCodecCtx->pix_fmt, ci->pCodecCtx->width, 
                        ci->pCodecCtx->height);
        
                    // Process the video frame (save to disk etc.)
                    //fprintf(stderr,"banan() New frame!\n");
                    //DoSomethingWithTheImage(ci->pFrameRGB);
                    return 0;
                }
            }
        
            // Free the packet that was allocated by av_read_frame
            av_free_packet(&ci->packet);
        }
        ci->is_done = 1;    
        return 0;
    } // if 0 != cleanup
    
    if (0 != cleanup) 
    {
        // Free the RGB image
        if (0 != ci->buffer) {
            av_free(ci->buffer);
            ci->buffer = 0;
        }
        if (0 != ci->pFrameRGB) {
            av_free(ci->pFrameRGB);
            ci->pFrameRGB = 0;
        } 
        
        // Close the codec
        if (0 != ci->pCodecCtx) {
            avcodec_close(ci->pCodecCtx);
            ci->pCodecCtx = 0;
        }
        
        // Close the video file
        if (0 != ci->pFormatCtx) {
            av_close_input_file(ci->pFormatCtx);    
            ci->pFormatCtx = 0;
        }
        
        ci->is_done = 0;
    }
    return 0;
}


void parse_arg_file(const char *filename)
{
}
