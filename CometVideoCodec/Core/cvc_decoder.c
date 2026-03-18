#include "cvc_engine.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <stdlib.h>
#include <string.h>

struct CVCDecoderContext {
  AVFormatContext *fmt_ctx;
  AVCodecContext *video_codec_ctx;
  AVCodecContext *audio_codec_ctx;
  int video_stream_idx;
  int audio_stream_idx;
  AVFrame *frame;
  AVFrame *audio_frame;
  AVFrame *audio_s16_frame;
  AVPacket *packet;
  SwrContext *swr_ctx;

  AVPacket **audio_queue;
  int audio_queue_size;
  int audio_queue_capacity;
};

const char *cvc_get_error_string(CVCResult result) {
  switch (result) {
  case CVC_SUCCESS:
    return "Success";
  case CVC_EOF:
    return "End of file";
  case CVC_ERROR_FILE_NOT_FOUND:
    return "File not found";
  case CVC_ERROR_INVALID_FORMAT:
    return "Invalid video format";
  case CVC_ERROR_NO_VIDEO_STREAM:
    return "No video stream found";
  case CVC_ERROR_DECODE:
    return "Decoding error";
  default:
    return "Unknown error";
  }
}

static void push_audio_packet(CVCDecoderContext *ctx, AVPacket *pkt) {
  if (ctx->audio_queue_size >= ctx->audio_queue_capacity) {
    int new_cap =
        ctx->audio_queue_capacity == 0 ? 32 : ctx->audio_queue_capacity * 2;
    AVPacket **new_queue =
        (AVPacket **)realloc(ctx->audio_queue, new_cap * sizeof(AVPacket *));
    if (!new_queue)
      return;
    ctx->audio_queue = new_queue;
    ctx->audio_queue_capacity = new_cap;
  }
  AVPacket *new_pkt = av_packet_alloc();
  av_packet_ref(new_pkt, pkt);
  ctx->audio_queue[ctx->audio_queue_size++] = new_pkt;
}

CVCDecoderContext *cvc_decoder_open(const char *filepath,
                                    CVCVideoInfo *out_info,
                                    CVCResult *out_result) {
  if (!filepath || !out_info || !out_result)
    return NULL;

  CVCDecoderContext *ctx =
      (CVCDecoderContext *)calloc(1, sizeof(CVCDecoderContext));
  if (!ctx) {
    *out_result = CVC_ERROR_DECODE;
    return NULL;
  }

  ctx->fmt_ctx = avformat_alloc_context();
  if (avformat_open_input(&ctx->fmt_ctx, filepath, NULL, NULL) < 0) {
    *out_result = CVC_ERROR_FILE_NOT_FOUND;
    cvc_decoder_close(ctx);
    return NULL;
  }

  if (avformat_find_stream_info(ctx->fmt_ctx, NULL) < 0) {
    *out_result = CVC_ERROR_INVALID_FORMAT;
    cvc_decoder_close(ctx);
    return NULL;
  }

  const AVCodec *vcodec = NULL;
  ctx->video_stream_idx =
      av_find_best_stream(ctx->fmt_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, &vcodec, 0);
  if (ctx->video_stream_idx < 0) {
    *out_result = CVC_ERROR_NO_VIDEO_STREAM;
    cvc_decoder_close(ctx);
    return NULL;
  }

  const AVCodec *acodec = NULL;
  ctx->audio_stream_idx =
      av_find_best_stream(ctx->fmt_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, &acodec, 0);

  AVStream *video_stream = ctx->fmt_ctx->streams[ctx->video_stream_idx];
  ctx->video_codec_ctx = avcodec_alloc_context3(vcodec);
  if (!ctx->video_codec_ctx) {
    *out_result = CVC_ERROR_DECODE;
    cvc_decoder_close(ctx);
    return NULL;
  }

  avcodec_parameters_to_context(ctx->video_codec_ctx, video_stream->codecpar);

  int threads = 0;
  cvc_system_optimize_threads(&threads);
  ctx->video_codec_ctx->thread_count = threads;
  ctx->video_codec_ctx->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;

  if (avcodec_open2(ctx->video_codec_ctx, vcodec, NULL) < 0) {
    *out_result = CVC_ERROR_DECODE;
    cvc_decoder_close(ctx);
    return NULL;
  }

  ctx->audio_codec_ctx = NULL;
  if (ctx->audio_stream_idx >= 0 && acodec) {
    AVStream *audio_stream = ctx->fmt_ctx->streams[ctx->audio_stream_idx];
    ctx->audio_codec_ctx = avcodec_alloc_context3(acodec);
    if (!ctx->audio_codec_ctx) { // Added check for allocation
      // Not a fatal error if audio codec context can't be allocated
      // Just proceed without audio decoding
    } else {
      avcodec_parameters_to_context(ctx->audio_codec_ctx,
                                    audio_stream->codecpar);
      if (avcodec_open2(ctx->audio_codec_ctx, acodec, NULL) < 0) {
        avcodec_free_context(&ctx->audio_codec_ctx);
        ctx->audio_codec_ctx = NULL;
      }
    }
  }

  ctx->frame = av_frame_alloc();
  ctx->audio_frame = av_frame_alloc();
  ctx->audio_s16_frame = av_frame_alloc();
  ctx->packet = av_packet_alloc();
  ctx->swr_ctx = NULL;

  if (ctx->audio_codec_ctx) {
    AVChannelLayout out_ch_layout = ctx->audio_codec_ctx->ch_layout;
    int out_sample_rate = ctx->audio_codec_ctx->sample_rate;

    swr_alloc_set_opts2(&ctx->swr_ctx, &out_ch_layout, AV_SAMPLE_FMT_S16,
                        out_sample_rate, &ctx->audio_codec_ctx->ch_layout,
                        ctx->audio_codec_ctx->sample_fmt, out_sample_rate, 0,
                        NULL);
    if (ctx->swr_ctx) {
      swr_init(ctx->swr_ctx);
    }
  }

  out_info->width = ctx->video_codec_ctx->width;
  out_info->height = ctx->video_codec_ctx->height;
  out_info->duration_sec = (double)ctx->fmt_ctx->duration / AV_TIME_BASE;
  if (video_stream->avg_frame_rate.den > 0) {
    out_info->framerate = av_q2d(video_stream->avg_frame_rate);
  } else {
    out_info->framerate = 30.0;
  }
  out_info->video_stream_index = ctx->video_stream_idx;
  out_info->audio_stream_index = ctx->audio_stream_idx;

  if (ctx->audio_codec_ctx) {
    out_info->sample_rate = ctx->audio_codec_ctx->sample_rate;
    out_info->channels = ctx->audio_codec_ctx->ch_layout.nb_channels;
  } else {
    out_info->sample_rate = 0;
    out_info->channels = 0;
  }

  *out_result = CVC_SUCCESS;
  return ctx;
}

CVCResult cvc_decoder_read_video_frame(CVCDecoderContext *ctx,
                                       CVCVideoFrame *out_frame) {
  if (!ctx || !out_frame)
    return CVC_ERROR_DECODE;

  int ret;
  while (1) {
    ret = avcodec_receive_frame(ctx->video_codec_ctx, ctx->frame);
    if (ret == 0) {
      AVFrame *out_av_frame = av_frame_alloc();
      av_frame_ref(out_av_frame, ctx->frame);

      out_frame->width = out_av_frame->width;
      out_frame->height = out_av_frame->height;

      AVStream *vs = ctx->fmt_ctx->streams[ctx->video_stream_idx];
      if (out_av_frame->pts != AV_NOPTS_VALUE) {
        out_frame->pts_sec = out_av_frame->pts * av_q2d(vs->time_base);
      } else {
        out_frame->pts_sec = 0.0;
      }

      out_frame->internal_frame = out_av_frame;

      for (int i = 0; i < 8; i++) {
        out_frame->data[i] = out_av_frame->data[i];
        out_frame->linesize[i] = out_av_frame->linesize[i];
      }
      return CVC_SUCCESS;
    }

    if (ret == AVERROR_EOF) {
      return CVC_EOF;
    }

    if (ret != AVERROR(EAGAIN)) {
      return CVC_ERROR_DECODE;
    }

    ret = av_read_frame(ctx->fmt_ctx, ctx->packet);
    if (ret == AVERROR_EOF) {
      avcodec_send_packet(ctx->video_codec_ctx, NULL);
      if (ctx->audio_codec_ctx)
        avcodec_send_packet(ctx->audio_codec_ctx, NULL);
    } else if (ret < 0) {
      return CVC_ERROR_DECODE;
    } else {
      if (ctx->packet->stream_index == ctx->video_stream_idx) {
        avcodec_send_packet(ctx->video_codec_ctx, ctx->packet);
      } else if (ctx->packet->stream_index == ctx->audio_stream_idx &&
                 ctx->audio_codec_ctx) {
        push_audio_packet(ctx, ctx->packet);
      }
      av_packet_unref(ctx->packet);
    }
  }
}

CVCResult cvc_decoder_read_audio_frame(CVCDecoderContext *ctx,
                                       CVCAudioFrame *out_frame) {
  if (!ctx || !out_frame || !ctx->audio_codec_ctx)
    return CVC_ERROR_DECODE;

  int ret;
  while (1) {
    ret = avcodec_receive_frame(ctx->audio_codec_ctx, ctx->audio_frame);
    if (ret == 0) {
      AVFrame *decoded = ctx->audio_frame;
      int channels = decoded->ch_layout.nb_channels;
      double pts_sec =
          decoded->pts *
          av_q2d(ctx->fmt_ctx->streams[ctx->audio_stream_idx]->time_base);

      if (ctx->swr_ctx &&
          decoded->format != AV_SAMPLE_FMT_S16) {
        AVFrame *s16 = ctx->audio_s16_frame;
        av_frame_unref(s16);
        s16->format = AV_SAMPLE_FMT_S16;
        s16->ch_layout = decoded->ch_layout;
        s16->sample_rate = decoded->sample_rate;
        s16->nb_samples = decoded->nb_samples;
        if (av_frame_get_buffer(s16, 0) < 0) {
          return CVC_ERROR_DECODE;
        }
        int converted = swr_convert(ctx->swr_ctx, s16->data, s16->nb_samples,
                                    (const uint8_t **)decoded->data,
                                    decoded->nb_samples);
        if (converted < 0) {
          return CVC_ERROR_DECODE;
        }
        s16->nb_samples = converted;

        AVFrame *out_av_frame = av_frame_alloc();
        av_frame_ref(out_av_frame, s16);
        out_av_frame->pts = decoded->pts;

        out_frame->nb_samples = converted;
        out_frame->channels = channels;
        out_frame->sample_rate = decoded->sample_rate;
        out_frame->pts_sec = pts_sec;
        out_frame->internal_frame = out_av_frame;
        for (int i = 0; i < 8; i++) {
          out_frame->data[i] = out_av_frame->data[i];
          out_frame->linesize[i] = out_av_frame->linesize[i];
        }
      } else {
        AVFrame *out_av_frame = av_frame_alloc();
        av_frame_ref(out_av_frame, decoded);
        out_frame->nb_samples = out_av_frame->nb_samples;
        out_frame->channels = channels;
        out_frame->sample_rate = out_av_frame->sample_rate;
        out_frame->pts_sec = pts_sec;
        out_frame->internal_frame = out_av_frame;
        for (int i = 0; i < 8; i++) {
          out_frame->data[i] = out_av_frame->data[i];
          out_frame->linesize[i] = out_av_frame->linesize[i];
        }
      }
      return CVC_SUCCESS;
    }

    if (ret == AVERROR_EOF)
      return CVC_EOF;
    if (ret != AVERROR(EAGAIN))
      return CVC_ERROR_DECODE;

    if (ctx->audio_queue_size > 0) {
      AVPacket *pkt = ctx->audio_queue[0];
      avcodec_send_packet(ctx->audio_codec_ctx, pkt);
      av_packet_free(&pkt);
      for (int i = 0; i < ctx->audio_queue_size - 1; i++)
        ctx->audio_queue[i] = ctx->audio_queue[i + 1];
      ctx->audio_queue_size--;
    } else {
      // We need more packets from the file.
      // But the loop in read_video_frame already feeds the audio queue.
      // If Swift asks for audio and queue is empty, we must read from source.
      ret = av_read_frame(ctx->fmt_ctx, ctx->packet);
      if (ret == AVERROR_EOF) {
        avcodec_send_packet(ctx->audio_codec_ctx, NULL);
      } else if (ret < 0) {
        return CVC_ERROR_DECODE;
      } else {
        if (ctx->packet->stream_index == ctx->audio_stream_idx) {
          avcodec_send_packet(ctx->audio_codec_ctx, ctx->packet);
        } else if (ctx->packet->stream_index == ctx->video_stream_idx) {
          // Buffer video packets? No, that's complex.
          // In a hybrid pull model, Swift usually asks for Video first.
          // If it asks for Audio and we find Video, we should just drop it or
          // return a special code. BUT: Professional video frames are huge, we
          // CAN'T drop them.
          return CVC_SUCCESS; // Signal "Try again after reading video" or
                              // similar
        }
        av_packet_unref(ctx->packet);
      }
    }
  }
}

int cvc_decoder_drain_audio_queue(CVCDecoderContext *ctx) {
  if (!ctx || !ctx->audio_codec_ctx)
    return 0;
  int drained = 0;
  while (1) {
    int ret = avcodec_receive_frame(ctx->audio_codec_ctx, ctx->audio_frame);
    if (ret == 0) {
      av_frame_unref(ctx->audio_frame);
      drained++;
      continue;
    }
    if (ret == AVERROR_EOF || ret != AVERROR(EAGAIN))
      return drained;
    if (ctx->audio_queue_size == 0)
      return drained;
    AVPacket *pkt = ctx->audio_queue[0];
    avcodec_send_packet(ctx->audio_codec_ctx, pkt);
    av_packet_free(&pkt);
    for (int i = 0; i < ctx->audio_queue_size - 1; i++)
      ctx->audio_queue[i] = ctx->audio_queue[i + 1];
    ctx->audio_queue_size--;
  }
}

CVCResult cvc_decoder_read_audio_packet(CVCDecoderContext *ctx,
                                        CVCAudioPacket *out_packet) {
  if (!ctx || !out_packet || ctx->audio_stream_idx < 0)
    return CVC_ERROR_DECODE;
  // (Previous implementation of packet passthrough, if still needed)
  return CVC_ERROR_DECODE; // Deprecated in favor of PCM decoding
}

void cvc_audio_packet_free(CVCAudioPacket *packet) {
  if (packet && packet->internal_packet) {
    AVPacket *pkt = (AVPacket *)packet->internal_packet;
    av_packet_free(&pkt);
    packet->internal_packet = NULL;
  }
}

void cvc_audio_frame_free(CVCAudioFrame *frame) {
  if (frame && frame->internal_frame) {
    AVFrame *av_frame = (AVFrame *)frame->internal_frame;
    av_frame_free(&av_frame);
    frame->internal_frame = NULL;
  }
}

void cvc_video_frame_free(CVCVideoFrame *frame) {
  if (frame && frame->internal_frame) {
    AVFrame *av_frame = (AVFrame *)frame->internal_frame;
    av_frame_free(&av_frame);
    frame->internal_frame = NULL;
  }
}

void cvc_decoder_close(CVCDecoderContext *ctx) {
  if (!ctx)
    return;
  if (ctx->swr_ctx)
    swr_free(&ctx->swr_ctx);
  if (ctx->frame)
    av_frame_free(&ctx->frame);
  if (ctx->audio_frame)
    av_frame_free(&ctx->audio_frame);
  if (ctx->audio_s16_frame)
    av_frame_free(&ctx->audio_s16_frame);
  if (ctx->packet)
    av_packet_free(&ctx->packet);
  if (ctx->video_codec_ctx)
    avcodec_free_context(&ctx->video_codec_ctx);
  if (ctx->audio_codec_ctx)
    avcodec_free_context(&ctx->audio_codec_ctx);
  if (ctx->fmt_ctx)
    avformat_close_input(&ctx->fmt_ctx);

  for (int i = 0; i < ctx->audio_queue_size; i++) {
    AVPacket *pkt = ctx->audio_queue[i];
    av_packet_free(&pkt);
  }
  free(ctx->audio_queue);
  free(ctx);
}
